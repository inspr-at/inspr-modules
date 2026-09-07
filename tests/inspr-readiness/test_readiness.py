# SPDX-License-Identifier: AGPL-3.0-only
"""Focused readiness contract, probe, cache, and redaction tests."""

from __future__ import annotations

import json
import os
import sys
import time
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from readiness.contract import (
    CONTRACT_VERSION,
    MAX_GENERATION_HOPS,
    ProfileError,
    digest_bytes,
    load_profile_bytes,
    parse_profile,
    usage_error_payload,
)
from readiness.engine import (
    ProbeHost,
    ProbeOutputBound,
    ProbeTimeout,
    RunResult,
    evaluate,
    generation_digest,
    operator_env,
    parse_runtime_doctor,
    run_closed,
    workspace_identity_digest,
)


NOW = datetime(2026, 9, 7, 14, 45, tzinfo=timezone.utc)
HEAD = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
STORE_ACTIVE = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-home-manager-generation"
STORE_INSTALLED = "/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-home-manager-generation"
KERNEL = "# AGENTS - Kernel\nbounded doctrine\n".encode("utf-8")


def kernel_digest() -> str:
    return digest_bytes(KERNEL)


def identities() -> dict[str, str]:
    return {
        "execution_host": "host-alpha",
        "runtime": "studio",
        "project": "INSPR",
        "account": "coordinator",
        "harness": "claude",
        "workspace": "wt-readiness",
    }


def base_profile(**overrides):
    payload = {
        "contract_version": CONTRACT_VERSION,
        "profile_id": "studio-dev",
        "identities": identities(),
        "expected": {
            "host_kind": "macos-home-manager",
            "home_manager_generation_digest": generation_digest(STORE_ACTIVE),
            "doctrine_kernel_digest": kernel_digest(),
            "doctrine_loader_ref": "@./doctrine/docs/AGENTS-KERNEL.md",
            "config_revision": "rev1",
            "paimos_instance": "studio",
            "paimos_deployment": "studio",
            "paimos_project_key": "INSPR",
            "account_label": "claude_ai_max",
            "harness": "claude",
            "model": "opus",
            "effort": "xhigh",
            "workspace_mode": "exclusive",
            "workspace_identity_digest": workspace_identity_digest(HEAD, is_worktree=True, mode="exclusive"),
            "tools": ["nix", "git", "paimos"],
        },
        "requested_capabilities": ["runtime_ready", "exclusive_workspace"],
        "checks": {
            "required": [
                "host_kind",
                "activated_generation",
                "doctrine_loader",
                "workspace_isolation",
                "tool_prerequisites",
                "paimos_runtime_doctor",
                "paimos_account",
            ],
            "optional": ["dispatch_profile"],
        },
        "inputs": {
            "workspace_root": "/fixture/workspace",
            "doctrine_kernel": "/fixture/workspace/doctrine/docs/AGENTS-KERNEL.md",
            "doctrine_loader": "/fixture/workspace/CLAUDE.md",
            "cache_dir": "/fixture/cache",
        },
        "observation_ttl_seconds": 300,
    }
    for key, value in overrides.items():
        if key in payload and isinstance(payload[key], dict) and isinstance(value, dict):
            merged = dict(payload[key])
            merged.update(value)
            payload[key] = merged
        else:
            payload[key] = value
    return payload


def doctor_layers(*, ready=True, auth="known", identity="known", extra=None):
    layers = [
        {"name": "cli_auth", "state": auth, "code": "named_auth_verified" if auth == "known" else "named_auth_unavailable"},
        {"name": "server_identity", "state": identity, "code": "authenticated_deployment_verified" if identity == "known" else "identity_unchecked"},
        {"name": "canonical_agents", "state": "known", "code": "canonical_agents_available"},
        {"name": "dispatch_profiles", "state": "known", "code": "immutable_profiles_available"},
        {"name": "targets", "state": "known", "code": "owned_target_consumers_verified"},
        {"name": "private_paths", "state": "known", "code": "private_owned_paths"},
        {"name": "daemon_service", "state": "known", "code": "verified_running_service"},
        {"name": "daemon_generation", "state": "known", "code": "live_owned_generation"},
        {"name": "socket_lock", "state": "known", "code": "live_instance_lock"},
        {"name": "journal", "state": "known", "code": "journal_valid"},
        {"name": "reporter_lease", "state": "known", "code": "authenticated_reporter_current"},
        {"name": "stale_generations", "state": "known", "code": "no_stale_generation_observed"},
        {"name": "workspace_ownership", "state": "known", "code": "owned_workspaces_verified"},
        {"name": "consumers", "state": "known", "code": "owned_consumers_ready"},
        {"name": "browser_intents", "state": "known", "code": "owned_lifecycle_executor_ready"},
        {"name": "primary_inbox", "state": "known", "code": "owned_primary_inbox_ready"},
        {"name": "repair_budget", "state": "known", "code": "repair_budget_available"},
    ]
    if extra:
        layers.extend(extra)
    return {
        "instance": "studio",
        "ready": ready,
        "bootstrap": "/Users/leak/paimos runtime setup --state-root /tmp/secret",
        "layers": layers,
    }


class FakeHost:
    def __init__(self) -> None:
        self.files: dict[str, bytes] = {}
        self.links: dict[str, str] = {}
        self.dirs: set[str] = set()
        self.which_map: dict[str, str] = {
            "git": "/nix/store/cccccccccccccccccccccccccccccccc-git/bin/git",
            "nix": "/nix/store/dddddddddddddddddddddddddddddddd-nix/bin/nix",
            "paimos": "/nix/store/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee-paimos/bin/paimos",
            "claude": "/nix/store/ffffffffffffffffffffffffffffffff-claude/bin/claude",
        }
        for path in self.which_map.values():
            self.files[path] = b"fake"
        self.git_head = HEAD
        self.git_dir = "/fixture/workspace/.git/worktrees/wt-readiness"
        self.git_common = "/fixture/workspace/.git"
        self.doctor = doctor_layers()
        self.claude_status = {"loggedIn": True, "authMethod": "claude.ai", "subscriptionType": "max"}
        self.codex_status = (b"Logged in using ChatGPT\n", b"", 0)
        self.timeout_names: set[str] = set()
        self.recorded: list[list[str]] = []
        self.environ = {"HOME": "/fixture/home", "USER": "operator", "PATH": "/nix/store/bin"}
        self.platform = "darwin"
        self.nixos_marker = False
        self._write_home_manager(STORE_ACTIVE, STORE_ACTIVE)
        self._write_doctrine()
        self.dirs.add("/fixture/workspace")
        self.dirs.add("/fixture/cache")

    def _write_home_manager(self, activated: str | None, installed: str | None) -> None:
        current = "/fixture/home/.local/state/home-manager/gcroots/current-home"
        profiles = "/fixture/home/.local/state/nix/profiles"
        profile = profiles + "/home-manager"
        gen_link = profiles + "/home-manager-78-link"
        for path in (current, profile, gen_link):
            self.links.pop(path, None)
        if activated:
            self.links[current] = activated
        if installed:
            self.links[profile] = "home-manager-78-link"
            self.links[gen_link] = installed

    def _write_doctrine(self) -> None:
        self.files["/fixture/workspace/doctrine/docs/AGENTS-KERNEL.md"] = KERNEL
        self.files["/fixture/workspace/CLAUDE.md"] = b"@./doctrine/docs/AGENTS-KERNEL.md\n"

    def which(self, name: str) -> str | None:
        return self.which_map.get(name)

    def exists(self, path: str) -> bool:
        return path in self.files or path in self.links or path in self.dirs

    def isdir(self, path: str) -> bool:
        return path in self.dirs

    def isfile(self, path: str) -> bool:
        return path in self.files or path in self.which_map.values()

    def islink(self, path: str) -> bool:
        return path in self.links

    def realpath(self, path: str) -> str:
        seen = set()
        current = path
        while current in self.links and current not in seen:
            seen.add(current)
            target = self.links[current]
            if not target.startswith("/"):
                current = os.path.normpath(os.path.join(os.path.dirname(current), target))
            else:
                current = target
        return current

    def readlink(self, path: str) -> str:
        return self.links[path]

    def listdir(self, path: str) -> list[str]:
        return []

    def read_file(self, path: str, limit: int) -> bytes:
        data = self.files[path]
        if len(data) > limit:
            raise ProfileError("input_too_large")
        return data

    def run(self, argv, *, timeout, max_output, extra_env=None, cwd=None):
        self.recorded.append(list(argv))
        name = os.path.basename(argv[0])
        if name in self.timeout_names:
            raise ProbeTimeout
        if name == "git":
            return self._git(argv)
        if name == "paimos":
            raw = json.dumps(self.doctor).encode("utf-8")
            if len(raw) > max_output:
                raise ProbeOutputBound
            return RunResult(tuple(argv), raw, b"", 0)
        if name == "claude":
            raw = json.dumps(self.claude_status).encode("utf-8")
            return RunResult(tuple(argv), raw, b"", 0)
        if name == "codex":
            stdout, stderr, code = self.codex_status
            return RunResult(tuple(argv), stdout, stderr, code)
        raise AssertionError(argv)

    def _git(self, argv: list[str]) -> RunResult:
        query = argv[-1]
        mapping = {
            "--is-inside-work-tree": "true",
            "HEAD": self.git_head,
            "--git-dir": self.git_dir,
            "--git-common-dir": self.git_common,
        }
        text = mapping.get(query, "")
        return RunResult(tuple(argv), (text + "\n").encode(), b"", 0 if text else 1)

    def as_probe(self) -> ProbeHost:
        return ProbeHost(
            which=self.which,
            run=self.run,
            read_file=self.read_file,
            isdir=self.isdir,
            isfile=self.isfile,
            islink=self.islink,
            realpath=self.realpath,
            readlink=self.readlink,
            environ=self.environ,
            platform=self.platform,
            nixos_marker=self.nixos_marker,
        )


def run_profile(payload, host: FakeHost, *, use_cache=False, now=NOW):
    profile = parse_profile(payload)
    return evaluate(profile, host.as_probe(), now=now, use_cache=use_cache)


class ContractTests(unittest.TestCase):
    def test_rejects_unknown_check_and_command_fields(self):
        payload = base_profile()
        payload["checks"]["required"] = ["host_kind", "shell_eval"]
        with self.assertRaises(ProfileError) as raised:
            parse_profile(payload)
        self.assertEqual(raised.exception.reason, "unknown_check")
        payload = base_profile()
        payload["exec"] = "rm -rf /"
        with self.assertRaises(ProfileError) as raised:
            parse_profile(payload)
        self.assertEqual(raised.exception.reason, "unknown_field")

    def test_doctrine_loader_ref_is_required_and_bounded(self):
        payload = base_profile()
        del payload["expected"]["doctrine_loader_ref"]
        with self.assertRaises(ProfileError) as raised:
            parse_profile(payload)
        self.assertEqual(raised.exception.reason, "missing_doctrine_loader_ref")
        payload = base_profile()
        payload["expected"]["doctrine_loader_ref"] = "@./doctrine/docs/AGENTS-PROFILE-CUSTOMER.md"
        with self.assertRaises(ProfileError) as raised:
            parse_profile(payload)
        self.assertEqual(raised.exception.reason, "invalid_doctrine_loader_ref")

    def test_rejects_path_attacks_and_oversize(self):
        payload = base_profile(inputs={"workspace_root": "/fixture/../etc/passwd"})
        with self.assertRaises(ProfileError) as raised:
            parse_profile(payload)
        self.assertEqual(raised.exception.reason, "unsafe_input_workspace_root")
        payload = base_profile(inputs={"workspace_root": "/fixture/workspace/./secret"})
        with self.assertRaises(ProfileError):
            parse_profile(payload)
        with self.assertRaises(ProfileError) as raised:
            load_profile_bytes(b"{" + (b"x" * 70000))
        self.assertEqual(raised.exception.reason, "profile_size")

    def test_rejects_shell_active_identities(self):
        payload = base_profile()
        payload["identities"]["project"] = "$(reboot)"
        with self.assertRaises(ProfileError):
            parse_profile(payload)

    def test_usage_error_is_value_free(self):
        payload = usage_error_payload("unsafe_input_workspace_root")
        encoded = json.dumps(payload)
        self.assertNotIn("/", encoded)
        self.assertNotIn("@", encoded)


class ProbeTests(unittest.TestCase):
    def test_ready_when_activated_and_native_evidence_matches(self):
        host = FakeHost()
        evidence = run_profile(base_profile(), host)
        self.assertEqual(evidence.status, "ready")
        self.assertEqual(evidence.next_action, "none")
        encoded = json.dumps(evidence.as_dict())
        self.assertNotIn("/fixture", encoded)
        self.assertNotIn("/Users/", encoded)
        self.assertNotIn("bootstrap", encoded)
        self.assertNotIn("leak", encoded)
        argv = [" ".join(item) for item in host.recorded]
        self.assertTrue(any("runtime doctor" in item for item in argv))
        self.assertFalse(any("inbox" in item or "auth login" in item for item in argv))

    def test_installed_but_not_activated_needs_setup(self):
        host = FakeHost()
        host._write_home_manager(None, STORE_INSTALLED)
        evidence = run_profile(base_profile(), host)
        self.assertEqual(evidence.status, "needs_setup")
        result = next(item for item in evidence.checks if item.id == "activated_generation")
        self.assertEqual(result.reason, "generation_not_activated")
        self.assertEqual(evidence.next_action, "activate_home_manager")

    def test_generation_digest_mismatch_is_not_ready(self):
        host = FakeHost()
        host._write_home_manager(STORE_INSTALLED, STORE_INSTALLED)
        evidence = run_profile(base_profile(), host)
        self.assertEqual(evidence.status, "needs_setup")
        result = next(item for item in evidence.checks if item.id == "activated_generation")
        self.assertEqual(result.reason, "generation_digest_mismatch")
        self.assertEqual(evidence.next_action, "activate_home_manager")

    def test_nixos_generation_digest_mismatch_hints_nixos_activation(self):
        payload = base_profile()
        payload["expected"]["host_kind"] = "nixos-home-manager"
        payload["expected"]["nix_system_generation_digest"] = generation_digest(
            "/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-nixos-system"
        )
        host = FakeHost()
        host.platform = "linux"
        host.nixos_marker = True
        host.links["/run/current-system"] = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system"
        host.links["/nix/var/nix/profiles/system"] = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system"
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "activated_generation")
        self.assertEqual(result.reason, "generation_digest_mismatch")
        self.assertEqual(evidence.next_action, "activate_nixos_generation")

    def test_doctrine_hash_drift(self):
        host = FakeHost()
        host.files["/fixture/workspace/doctrine/docs/AGENTS-KERNEL.md"] = b"drifted kernel\n"
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "doctrine_loader")
        self.assertEqual(result.reason, "doctrine_hash_mismatch")
        self.assertEqual(evidence.status, "needs_setup")

    def test_doctrine_loader_unwired(self):
        host = FakeHost()
        host.files["/fixture/workspace/CLAUDE.md"] = b"@./doctrine/docs/AGENTS-CORE.md\n"
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "doctrine_loader")
        self.assertEqual(result.reason, "doctrine_loader_unwired")

    def test_wrong_workspace_identity(self):
        host = FakeHost()
        host.git_head = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "workspace_isolation")
        self.assertEqual(result.reason, "workspace_identity_mismatch")

    def test_wrong_account_label(self):
        host = FakeHost()
        host.claude_status["subscriptionType"] = "pro"
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "paimos_account")
        self.assertEqual(result.status, "fail")
        self.assertEqual(result.reason, "account_mismatch")

    def test_named_account_is_unavailable_without_native_integration(self):
        payload = base_profile(requested_capabilities=["runtime_ready", "named_account"])
        payload["expected"]["account_key"] = "coordinator"
        host = FakeHost()
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "paimos_account")
        self.assertEqual(result.status, "unsupported")
        self.assertEqual(result.reason, "missing_integration_paimos_named_account_probe")
        self.assertEqual(evidence.status, "unavailable")

    def test_optional_dispatch_profile_warns_without_demoting_ready(self):
        host = FakeHost()
        evidence = run_profile(base_profile(), host)
        optional = next(item for item in evidence.checks if item.id == "dispatch_profile")
        self.assertEqual(optional.status, "warn")
        self.assertEqual(optional.reason, "missing_integration_paimos_dispatch_profile_match")
        self.assertEqual(evidence.status, "ready")

    def test_required_unknown_doctor_layer_cannot_be_ready(self):
        host = FakeHost()
        host.doctor = doctor_layers(ready=True, auth="unknown")
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "paimos_runtime_doctor")
        self.assertEqual(result.status, "unknown")
        self.assertEqual(evidence.status, "unavailable")

    def test_browser_ready_boolean_is_not_authority(self):
        host = FakeHost()
        host.doctor = doctor_layers(ready=True, auth="unknown", identity="unknown")
        evidence = run_profile(base_profile(), host)
        self.assertNotEqual(evidence.status, "ready")
        self.assertEqual(evidence.status, "unavailable")

    def test_invalid_doctor_json_is_unknown(self):
        host = FakeHost()
        host.doctor = {"ready": True, "ok": True}
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "paimos_runtime_doctor")
        self.assertEqual(result.reason, "runtime_evidence_invalid")
        self.assertEqual(evidence.status, "unavailable")

    def test_doctor_paths_are_redacted(self):
        parsed = parse_runtime_doctor(json.dumps(doctor_layers()).encode())
        self.assertIsNotNone(parsed)
        encoded = json.dumps(parsed)
        self.assertNotIn("/Users/", encoded)
        self.assertNotIn("bootstrap", encoded)

    def test_timeout_is_unknown(self):
        host = FakeHost()
        host.timeout_names.add("paimos")
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "paimos_runtime_doctor")
        self.assertEqual(result.status, "unknown")
        self.assertEqual(result.reason, "probe_timeout")
        self.assertEqual(evidence.status, "unavailable")

    def test_non_nix_host_is_unavailable(self):
        host = FakeHost()
        host.platform = "linux"
        host.nixos_marker = False
        evidence = run_profile(base_profile(expected={"host_kind": "macos-home-manager"}), host)
        result = next(item for item in evidence.checks if item.id == "host_kind")
        self.assertEqual(result.status, "unsupported")
        self.assertEqual(result.reason, "non_nix_onboarding_unavailable")
        self.assertEqual(evidence.status, "unavailable")
        self.assertEqual(evidence.next_action, "adopt_nix_home_manager")

    def test_nixos_profile_on_macos_is_unavailable(self):
        payload = base_profile()
        payload["expected"]["host_kind"] = "nixos-home-manager"
        payload["expected"]["nix_system_generation_digest"] = generation_digest(
            "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system"
        )
        host = FakeHost()
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "host_kind")
        self.assertEqual(result.reason, "nixos_unavailable_on_macos")
        self.assertEqual(evidence.status, "unavailable")

    def test_expired_or_forged_cache_cannot_change_results(self):
        host = FakeHost()
        payload = base_profile()
        first = run_profile(payload, host, use_cache=True, now=NOW)
        self.assertEqual(first.status, "ready")
        first_probes = len(host.recorded)
        host.files["/fixture/cache/forged.json"] = json.dumps(
            {
                "status": "ready",
                "checks": [{"id": "host_kind", "status": "pass", "reason": "host_kind_supported"}],
            }
        ).encode()
        later = run_profile(payload, host, use_cache=True, now=NOW + timedelta(seconds=301))
        self.assertEqual(later.status, "ready")
        self.assertGreater(len(host.recorded), first_probes)
        self.assertFalse(any(item.status == "stale" for item in later.checks))
        host._write_home_manager(None, STORE_INSTALLED)
        broken = run_profile(payload, host, use_cache=True, now=NOW + timedelta(seconds=302))
        self.assertEqual(broken.status, "needs_setup")
        result = next(item for item in broken.checks if item.id == "activated_generation")
        self.assertEqual(result.reason, "generation_not_activated")

    def test_darwin_without_home_manager_does_not_claim_supported_class(self):
        host = FakeHost()
        host._write_home_manager(None, None)
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "host_kind")
        self.assertEqual(result.status, "fail")
        self.assertEqual(result.reason, "host_kind_mismatch")
        self.assertNotEqual(evidence.status, "ready")

    def test_relative_home_manager_chain_matches_activated_store(self):
        host = FakeHost()
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "activated_generation")
        self.assertEqual(result.status, "pass")
        self.assertEqual(result.reason, "generation_activated")
        self.assertEqual(result.digest, generation_digest(STORE_ACTIVE))

    def test_generation_symlink_cycle_is_unresolved(self):
        host = FakeHost()
        current = "/fixture/home/.local/state/home-manager/gcroots/current-home"
        other = "/fixture/home/.local/state/home-manager/gcroots/loop"
        host.links[current] = other
        host.links[other] = current
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "activated_generation")
        self.assertEqual(result.reason, "generation_not_activated")
        self.assertEqual(evidence.status, "needs_setup")

    def test_generation_hop_bound(self):
        host = FakeHost()
        start = "/fixture/home/.local/state/home-manager/gcroots/current-home"
        chain = [start] + [f"/fixture/home/.local/state/nix/profiles/hop-{i}" for i in range(MAX_GENERATION_HOPS)]
        for src, dst in zip(chain, chain[1:] + [STORE_ACTIVE]):
            host.links[src] = dst
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "activated_generation")
        self.assertEqual(result.reason, "generation_not_activated")

    def test_nixos_relative_system_chain_resolves(self):
        payload = base_profile()
        payload["expected"]["host_kind"] = "nixos-home-manager"
        payload["expected"]["nix_system_generation_digest"] = generation_digest(
            "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system"
        )
        host = FakeHost()
        host.platform = "linux"
        host.nixos_marker = True
        host._write_home_manager(STORE_ACTIVE, STORE_ACTIVE)
        host.links["/run/current-system"] = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system"
        host.links["/nix/var/nix/profiles/system"] = "system-42-link"
        host.links["/nix/var/nix/profiles/system-42-link"] = (
            "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system"
        )
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "activated_generation")
        self.assertEqual(result.status, "pass")
        host_kind = next(item for item in evidence.checks if item.id == "host_kind")
        self.assertEqual(host_kind.status, "pass")

    def test_doctrine_loader_ref_comes_from_profile(self):
        payload = base_profile()
        payload["expected"]["doctrine_loader_ref"] = "@./docs/AGENTS-KERNEL.md"
        host = FakeHost()
        host.files["/fixture/workspace/CLAUDE.md"] = b"@./docs/AGENTS-KERNEL.md\n"
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "doctrine_loader")
        self.assertEqual(result.status, "pass")

    def test_generic_profile_autoload_is_legacy(self):
        host = FakeHost()
        host.files["/fixture/workspace/CLAUDE.md"] = (
            b"@./doctrine/docs/AGENTS-KERNEL.md\n@./doctrine/docs/AGENTS-PROFILE-CUSTOMER.md\n"
        )
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "doctrine_loader")
        self.assertEqual(result.reason, "doctrine_loader_legacy")

    def test_unknown_future_doctor_layer_is_ignored_after_schema(self):
        host = FakeHost()
        host.doctor = doctor_layers(extra=[{"name": "future_layer", "state": "unknown", "code": "new_check"}])
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "paimos_runtime_doctor")
        self.assertEqual(result.status, "pass")
        self.assertEqual(evidence.status, "ready")

    def test_invalid_unknown_doctor_layer_voids_report(self):
        host = FakeHost()
        host.doctor = doctor_layers(extra=[{"name": "not a layer", "state": "known", "code": "layer_ok"}])
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "paimos_runtime_doctor")
        self.assertEqual(result.reason, "runtime_evidence_invalid")
        self.assertEqual(evidence.status, "unavailable")

    def test_codex_requires_documented_status_line(self):
        payload = base_profile()
        payload["expected"]["harness"] = "codex"
        payload["expected"]["account_label"] = "chatgpt"
        host = FakeHost()
        host.which_map["codex"] = "/nix/store/ffffffffffffffffffffffffffffffff-codex/bin/codex"
        host.files[host.which_map["codex"]] = b"fake"
        host.codex_status = (b"Logged in using ChatGPT\n", b"", 0)
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "paimos_account")
        self.assertEqual(result.status, "pass")

    def test_codex_help_or_api_key_substring_is_not_auth(self):
        payload = base_profile()
        payload["expected"]["harness"] = "codex"
        payload["expected"]["account_label"] = "api_key"
        host = FakeHost()
        host.which_map["codex"] = "/nix/store/ffffffffffffffffffffffffffffffff-codex/bin/codex"
        host.files[host.which_map["codex"]] = b"fake"
        host.codex_status = (b"use `codex login --api-key` to authenticate\n", b"", 0)
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "paimos_account")
        self.assertEqual(result.status, "unknown")
        self.assertEqual(result.reason, "account_label_unknown")
        self.assertEqual(evidence.status, "unavailable")

    def test_codex_stderr_api_key_mention_without_status_is_unknown(self):
        payload = base_profile()
        payload["expected"]["harness"] = "codex"
        payload["expected"]["account_label"] = "api_key"
        host = FakeHost()
        host.which_map["codex"] = "/nix/store/ffffffffffffffffffffffffffffffff-codex/bin/codex"
        host.files[host.which_map["codex"]] = b"fake"
        host.codex_status = (b"", b"missing api_key in environment\n", 0)
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "paimos_account")
        self.assertEqual(result.reason, "account_label_unknown")
        self.assertEqual(evidence.status, "unavailable")

    def test_codex_conflicting_streams_are_unknown(self):
        payload = base_profile()
        payload["expected"]["harness"] = "codex"
        payload["expected"]["account_label"] = "chatgpt"
        host = FakeHost()
        host.which_map["codex"] = "/nix/store/ffffffffffffffffffffffffffffffff-codex/bin/codex"
        host.files[host.which_map["codex"]] = b"fake"
        host.codex_status = (b"Logged in using ChatGPT\n", b"Logged in using an API key - suffix\n", 0)
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "paimos_account")
        self.assertEqual(result.reason, "account_probe_invalid")
        self.assertEqual(evidence.status, "unavailable")

    def test_named_account_stays_missing_integration_on_codex(self):
        payload = base_profile(requested_capabilities=["runtime_ready", "named_account"])
        payload["expected"]["harness"] = "codex"
        payload["expected"]["account_label"] = "chatgpt"
        payload["expected"]["account_key"] = "coordinator"
        host = FakeHost()
        host.which_map["codex"] = "/nix/store/ffffffffffffffffffffffffffffffff-codex/bin/codex"
        host.files[host.which_map["codex"]] = b"fake"
        host.codex_status = (b"Logged in using ChatGPT\n", b"", 0)
        evidence = run_profile(payload, host)
        result = next(item for item in evidence.checks if item.id == "paimos_account")
        self.assertEqual(result.reason, "missing_integration_paimos_named_account_probe")
        self.assertEqual(evidence.status, "unavailable")

    def test_workspace_executables_are_refused(self):
        host = FakeHost()
        host.which_map["nix"] = "/fixture/workspace/result/bin/nix"
        host.files["/fixture/workspace/result/bin/nix"] = b"repo wrapper"
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "tool_prerequisites")
        self.assertEqual(result.reason, "workspace_executable_refused")

    def test_operator_env_drops_blocked_names(self):
        env = operator_env(
            {
                "PATH": "/nix/store/bin",
                "HOME": "/fixture/home",
                "PAIMOS_API_KEY": "fixture-blocked-token",
                "OPENAI_API_KEY": "fixture-blocked-token",
                "SECRET_EXTRA": "fixture-blocked-token",
            }
        )
        self.assertEqual(env["PATH"], "/nix/store/bin")
        self.assertEqual(env["HOME"], "/fixture/home")
        self.assertNotIn("PAIMOS_API_KEY", env)
        self.assertNotIn("OPENAI_API_KEY", env)
        self.assertNotIn("SECRET_EXTRA", env)

    def test_run_closed_subprocess_env_omits_blocked_names(self):
        result = run_closed(
            [sys.executable, "-c", "import os; print('\\n'.join(sorted(os.environ)))"],
            timeout=5,
            max_output=65536,
            environ={
                "PATH": os.environ.get("PATH", "/usr/bin"),
                "HOME": "/fixture/home",
                "PAIMOS_API_KEY": "fixture-blocked-token",
                "OPENAI_API_KEY": "fixture-blocked-token",
            },
        )
        names = result.stdout.decode("utf-8").splitlines()
        self.assertIn("PATH", names)
        self.assertIn("HOME", names)
        self.assertNotIn("PAIMOS_API_KEY", names)
        self.assertNotIn("OPENAI_API_KEY", names)
        self.assertNotIn("fixture-blocked-token", result.stdout.decode("utf-8"))
        self.assertNotIn("fixture-blocked-token", result.stderr.decode("utf-8"))


class RunClosedBoundaryTests(unittest.TestCase):
    _ENV = {
        "PATH": os.environ.get("PATH", "/usr/bin"),
        "HOME": "/fixture/home",
    }

    def test_output_bound_stops_flooding_stdout_quickly(self):
        script = (
            "import sys\n"
            "while True:\n"
            "    sys.stdout.write('x' * 4096)\n"
            "    sys.stdout.flush()\n"
        )
        started = time.monotonic()
        with self.assertRaises(ProbeOutputBound):
            run_closed(
                [sys.executable, "-c", script],
                timeout=30,
                max_output=8192,
                environ=self._ENV,
            )
        self.assertLess(time.monotonic() - started, 5.0)

    def test_combined_stdout_stderr_budget(self):
        script = (
            "import sys\n"
            "sys.stdout.write('a' * 7000)\n"
            "sys.stdout.flush()\n"
            "sys.stderr.write('b' * 7000)\n"
            "sys.stderr.flush()\n"
        )
        with self.assertRaises(ProbeOutputBound):
            run_closed(
                [sys.executable, "-c", script],
                timeout=5,
                max_output=8192,
                environ=self._ENV,
            )

    def test_binary_output_and_exit_codes(self):
        script = "import sys; sys.stdout.buffer.write(bytes(range(256))); sys.exit(17)"
        result = run_closed(
            [sys.executable, "-c", script],
            timeout=5,
            max_output=512,
            environ=self._ENV,
        )
        self.assertEqual(result.exit_code, 17)
        self.assertEqual(result.stdout, bytes(range(256)))
        self.assertEqual(result.stderr, b"")

    def test_timeout_stops_runaway_process(self):
        script = "import time\nwhile True:\n    time.sleep(0.01)\n"
        started = time.monotonic()
        with self.assertRaises(ProbeTimeout):
            run_closed(
                [sys.executable, "-c", script],
                timeout=1,
                max_output=65536,
                environ=self._ENV,
            )
        self.assertLess(time.monotonic() - started, 5.0)

    def test_retained_pipe_writer_does_not_hang_or_emit_late_marker(self):
        import tempfile

        marker = Path(tempfile.mkdtemp()) / "late-marker"
        script = (
            "import os, sys\n"
            f"marker = {str(marker)!r}\n"
            "if os.fork() == 0:\n"
            "    os.setsid()\n"
            "    try:\n"
            "        while True:\n"
            "            os.write(1, b'z' * 4096)\n"
            "    except OSError:\n"
            "        os._exit(0)\n"
            "    open(marker, 'w', encoding='utf-8').write('late')\n"
            "    os._exit(0)\n"
            "sys.stdout.write('EARLY\\n')\n"
            "sys.stdout.flush()\n"
            "while True:\n"
            "    sys.stdout.write('LATE\\n')\n"
            "    sys.stdout.flush()\n"
        )
        started = time.monotonic()
        with self.assertRaises(ProbeOutputBound):
            run_closed(
                [sys.executable, "-c", script],
                timeout=5,
                max_output=8192,
                environ=self._ENV,
            )
        self.assertLess(time.monotonic() - started, 2.0)
        self.assertFalse(marker.exists())


class CacheIgnoreTests(unittest.TestCase):
    def test_forged_ready_cache_cannot_promote_broken_host(self):
        host = FakeHost()
        payload = base_profile()
        profile = parse_profile(payload)
        host.files["/fixture/cache/" + profile.digest[7:] + ".json"] = json.dumps(
            {
                "cache_schema": "inspr.readiness.cache.v1",
                "profile_digest": profile.digest,
                "context": identities(),
                "expected_revisions": dict(parse_profile(payload).expected),
                "evidence": {
                    "status": "ready",
                    "checks": [
                        {"id": check_id, "status": "pass", "reason": "host_kind_supported"}
                        for check_id in payload["checks"]["required"]
                    ],
                },
            }
        ).encode()
        host.files["/fixture/workspace/doctrine/docs/AGENTS-KERNEL.md"] = b"drifted kernel\n"
        host._write_home_manager(None, STORE_INSTALLED)
        evidence = evaluate(profile, host.as_probe(), now=NOW, use_cache=True)
        self.assertNotEqual(evidence.status, "ready")
        self.assertTrue(host.recorded)


if __name__ == "__main__":
    unittest.main()
