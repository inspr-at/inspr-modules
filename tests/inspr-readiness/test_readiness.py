# SPDX-License-Identifier: AGPL-3.0-only
"""Focused readiness contract, probe, cache, and redaction tests."""

from __future__ import annotations

import json
import os
import stat
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from readiness.contract import (
    CONTRACT_VERSION,
    ProfileError,
    digest_bytes,
    digest_text,
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
    parse_runtime_doctor,
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
        profile = "/fixture/home/.local/state/nix/profiles/home-manager"
        self.links.pop(current, None)
        self.links.pop(profile, None)
        if activated:
            self.links[current] = activated
        if installed:
            self.links[profile] = installed

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
            current = self.links[current]
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
            exists=self.exists,
            isdir=self.isdir,
            isfile=self.isfile,
            islink=self.islink,
            realpath=self.realpath,
            readlink=self.readlink,
            listdir=self.listdir,
            environ=self.environ,
            platform=self.platform,
            nixos_marker=self.nixos_marker,
            makedirs=lambda path: self.dirs.add(path),
            write_file=lambda path, data: self.files.__setitem__(path, data),
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

    def test_stale_cache_cannot_be_ready(self):
        host = FakeHost()
        payload = base_profile()
        first = run_profile(payload, host, use_cache=True, now=NOW)
        self.assertEqual(first.status, "ready")
        stale_now = NOW + timedelta(seconds=301)
        evidence = run_profile(payload, host, use_cache=True, now=stale_now)
        self.assertEqual(evidence.status, "unavailable")
        self.assertTrue(
            any(item.status == "stale" for item in evidence.checks if item.id in payload["checks"]["required"])
        )

    def test_workspace_executables_are_refused(self):
        host = FakeHost()
        host.which_map["nix"] = "/fixture/workspace/result/bin/nix"
        host.files["/fixture/workspace/result/bin/nix"] = b"repo wrapper"
        evidence = run_profile(base_profile(), host)
        result = next(item for item in evidence.checks if item.id == "tool_prerequisites")
        self.assertEqual(result.reason, "declared_tool_missing")

    def test_paimos_env_is_not_forwarded(self):
        recorded_env = {}

        def run(argv, *, timeout, max_output, extra_env=None, cwd=None):
            recorded_env.update(extra_env or {})
            return RunResult(tuple(argv), json.dumps(doctor_layers()).encode(), b"", 0)

        host = FakeHost()
        probe = host.as_probe()
        probe.run = run  # type: ignore[method-assign]
        # operator_env is applied inside run_closed, not FakeHost.run. Direct probe uses FakeHost.
        self.assertNotIn("PAIMOS_API_KEY", host.environ)


class CacheInvalidateTests(unittest.TestCase):
    def test_revision_change_invalidates_cache(self):
        host = FakeHost()
        payload = base_profile()
        profile = parse_profile(payload)
        first = evaluate(profile, host.as_probe(), now=NOW, use_cache=False)
        cache_name = profile.digest[7:] + ".json"
        cached = {
            "cache_schema": "inspr.readiness.cache.v1",
            "profile_digest": profile.digest,
            "context": identities(),
            "expected_revisions": dict(first.expected_revisions),
            "evidence": first.as_dict(),
        }
        host.files["/fixture/cache/" + cache_name] = json.dumps(cached).encode()
        payload["expected"]["config_revision"] = "rev2"
        payload["expected"]["doctrine_kernel_digest"] = kernel_digest()
        drifted = parse_profile(payload)
        self.assertNotEqual(drifted.digest, profile.digest)
        evidence = evaluate(drifted, host.as_probe(), now=NOW, use_cache=True)
        # New profile digest misses the old cache file and re-probes.
        self.assertEqual(evidence.profile_digest, drifted.digest)
        self.assertEqual(evidence.expected_revisions["config_revision"], "rev2")


if __name__ == "__main__":
    unittest.main()
