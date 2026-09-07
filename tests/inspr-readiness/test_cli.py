# SPDX-License-Identifier: AGPL-3.0-only
"""Exercise the real readiness CLI with isolated deterministic fixtures."""

from __future__ import annotations

import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from readiness.contract import CONTRACT_VERSION, digest_bytes
from readiness.engine import generation_digest, workspace_identity_digest


def _readiness_pythonpath() -> str:
    for entry in os.environ.get("PYTHONPATH", "").split(os.pathsep):
        if entry and (Path(entry) / "readiness").is_dir():
            return entry
    return str(Path(__file__).resolve().parents[2] / "pkgs" / "inspr")


PYTHONPATH = _readiness_pythonpath()
KERNEL = "# AGENTS - Kernel\nbounded doctrine\n".encode("utf-8")


def run_cli(profile: Path, env: dict[str, str], extra: list[str] | None = None) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, "-m", "readiness", "--profile", str(profile), "--json", "--no-cache"]
    if extra:
        command.extend(extra)
    merged = os.environ.copy()
    merged.update(env)
    merged["PYTHONPATH"] = PYTHONPATH + (os.pathsep + merged["PYTHONPATH"] if merged.get("PYTHONPATH") else "")
    return subprocess.run(command, check=False, text=True, capture_output=True, env=merged)


class RealCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmpdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tmpdir.name)
        self.home = self.root / "home"
        self.workspace = self.root / "workspace"
        self.bin = self.root / "bin"
        self.cache = self.root / "cache"
        for path in (self.home, self.workspace, self.bin, self.cache):
            path.mkdir(parents=True)
        (self.workspace / "doctrine" / "docs").mkdir(parents=True)
        (self.workspace / "doctrine" / "docs" / "AGENTS-KERNEL.md").write_bytes(KERNEL)
        (self.workspace / "CLAUDE.md").write_text("@./doctrine/docs/AGENTS-KERNEL.md\n", encoding="utf-8")
        subprocess.run(["git", "init", "-q", str(self.workspace)], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(self.workspace),
                "-c",
                "user.name=ReadinessFixture",
                "-c",
                "user.email=dev@example.invalid",
                "config",
                "commit.gpgsign",
                "false",
            ],
            check=True,
        )
        subprocess.run(["git", "-C", str(self.workspace), "add", "CLAUDE.md", "doctrine/docs/AGENTS-KERNEL.md"], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(self.workspace),
                "-c",
                "user.name=ReadinessFixture",
                "-c",
                "user.email=dev@example.invalid",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "-q",
                "-m",
                "fixture",
            ],
            check=True,
        )
        head = subprocess.check_output(["git", "-C", str(self.workspace), "rev-parse", "HEAD"], text=True).strip()
        git_dir = subprocess.check_output(["git", "-C", str(self.workspace), "rev-parse", "--git-dir"], text=True).strip()
        common = subprocess.check_output(["git", "-C", str(self.workspace), "rev-parse", "--git-common-dir"], text=True).strip()
        self.head = head
        self.workspace_digest = workspace_identity_digest(head, is_worktree=git_dir != common, mode="exclusive")
        store = "/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-home-manager-generation"
        current = self.home / ".local/state/home-manager/gcroots/current-home"
        profiles = self.home / ".local/state/nix/profiles"
        profile = profiles / "home-manager"
        generation_link = profiles / "home-manager-78-link"
        current.parent.mkdir(parents=True)
        profiles.mkdir(parents=True)
        current.symlink_to(store)
        profile.symlink_to("home-manager-78-link")
        generation_link.symlink_to(store)
        self.generation = generation_digest(store)
        self._write_tool("paimos", self._paimos_script())
        self._write_tool("claude", self._claude_script())
        self._write_tool("nix", "#!/bin/sh\nexit 0\n")
        self.env = {
            "HOME": str(self.home),
            "USER": "operator",
            "PATH": str(self.bin) + os.pathsep + os.environ.get("PATH", ""),
            "XDG_CACHE_HOME": str(self.cache),
            "INSPR_READINESS_NOW": "2026-09-07T14:45:00Z",
        }

    def tearDown(self) -> None:
        self.tmpdir.cleanup()

    def _write_tool(self, name: str, body: str) -> None:
        path = self.bin / name
        path.write_text(body, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IEXEC)

    def _paimos_script(self) -> str:
        report = {
            "instance": "studio",
            "ready": True,
            "bootstrap": "/Users/leak/should-not-export",
            "layers": [
                {"name": name, "state": "known", "code": "named_auth_verified" if name == "cli_auth" else "authenticated_deployment_verified" if name == "server_identity" else "layer_ok"}
                for name in (
                    "cli_auth",
                    "server_identity",
                    "canonical_agents",
                    "dispatch_profiles",
                    "targets",
                    "private_paths",
                    "daemon_service",
                    "daemon_generation",
                    "socket_lock",
                    "journal",
                    "reporter_lease",
                    "stale_generations",
                    "workspace_ownership",
                    "consumers",
                    "browser_intents",
                    "primary_inbox",
                    "repair_budget",
                )
            ],
        }
        return f"""#!/bin/sh
test "$1" = --json -a "$2" = --instance -a "$4" = runtime -a "$5" = doctor || exit 9
# refuse ambient credentials and inbox/message verbs
env | grep -E '^(PAIMOS_API_KEY|PPMAPIKEY)=' && exit 8
printf '%s\\n' '{json.dumps(report)}'
"""

    def _claude_script(self) -> str:
        return """#!/bin/sh
test "$1" = auth -a "$2" = status -a "$3" = --json || exit 9
printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"max"}'
"""

    def _profile(self, **expected_overlay) -> Path:
        expected = {
            "host_kind": "macos-home-manager",
            "home_manager_generation_digest": self.generation,
            "doctrine_kernel_digest": digest_bytes(KERNEL),
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
            "workspace_identity_digest": self.workspace_digest,
            "tools": ["nix", "git", "paimos"],
        }
        expected.update(expected_overlay)
        payload = {
            "contract_version": CONTRACT_VERSION,
            "profile_id": "studio-dev",
            "identities": {
                "execution_host": "host-alpha",
                "runtime": "studio",
                "project": "INSPR",
                "account": "coordinator",
                "harness": "claude",
                "workspace": "wt-readiness",
            },
            "expected": expected,
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
                "workspace_root": str(self.workspace),
                "doctrine_kernel": str(self.workspace / "doctrine/docs/AGENTS-KERNEL.md"),
                "doctrine_loader": str(self.workspace / "CLAUDE.md"),
                "cache_dir": str(self.cache),
            },
            "observation_ttl_seconds": 300,
        }
        path = self.root / "profile.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_real_cli_ready_on_macos_home_manager_fixture(self):
        if sys.platform != "darwin":
            self.skipTest("first-supported live CLI host class is macOS Home Manager")
        result = run_cli(self._profile(), self.env)
        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(payload["status"], "ready")
        self.assertNotIn("/Users/", result.stdout)
        self.assertNotIn("should-not-export", result.stdout)
        self.assertNotIn("dev@example.invalid", result.stdout)

    def test_missing_profile_is_usage_error_without_path_or_traceback(self):
        missing = self.root / "definitely-not-here.json"
        result = run_cli(missing, self.env)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stdout)
        self.assertNotIn("Traceback", result.stderr)
        error = json.loads(result.stdout)
        self.assertEqual(error["error"], "profile_invalid")
        self.assertEqual(error["reason"], "unreadable_profile")
        self.assertNotIn(str(missing), result.stdout)
        self.assertNotIn(str(missing), result.stderr)
        self.assertNotIn("/Users/", result.stdout + result.stderr)

    def test_directory_profile_is_usage_error_without_path_or_traceback(self):
        result = run_cli(self.root, self.env)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stdout)
        self.assertNotIn("Traceback", result.stderr)
        error = json.loads(result.stdout)
        self.assertEqual(error["error"], "profile_invalid")
        self.assertEqual(error["reason"], "unsafe_profile_path")
        self.assertNotIn(str(self.root), result.stdout)
        self.assertNotIn(str(self.root), result.stderr)

    def test_unreadable_profile_is_usage_error_without_path(self):
        path = self.root / "secret-profile.json"
        path.write_text("{}", encoding="utf-8")
        path.chmod(0)
        try:
            result = run_cli(path, self.env)
        finally:
            path.chmod(0o600)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn("Traceback", result.stdout + result.stderr)
        error = json.loads(result.stdout)
        self.assertEqual(error["error"], "profile_invalid")
        self.assertIn(error["reason"], {"unreadable_profile", "profile_json"})
        self.assertNotIn(str(path), result.stdout)
        self.assertNotIn(str(path), result.stderr)

    def test_forged_cache_does_not_change_cli_observation(self):
        if sys.platform != "darwin":
            self.skipTest("first-supported live CLI host class is macOS Home Manager")
        profile = self._profile()
        cache_file = self.cache / "forged-ready.json"
        cache_file.write_text(
            json.dumps({"status": "ready", "checks": [{"id": "host_kind", "status": "pass", "reason": "host_kind_supported"}]}),
            encoding="utf-8",
        )
        result = run_cli(profile, self.env)
        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(payload["status"], "ready")
        current = self.home / ".local/state/home-manager/gcroots/current-home"
        current.unlink()
        broken = run_cli(profile, self.env)
        broken_payload = json.loads(broken.stdout)
        self.assertEqual(broken.returncode, 1)
        self.assertEqual(broken_payload["status"], "needs_setup")
        generation = next(item for item in broken_payload["checks"] if item["id"] == "activated_generation")
        self.assertEqual(generation["reason"], "generation_not_activated")

    def test_real_cli_rejects_relative_path_escape(self):
        bad = self.root / "bad.json"
        payload = json.loads(self._profile().read_text())
        payload["inputs"]["workspace_root"] = str(self.workspace / ".." / "etc")
        bad.write_text(json.dumps(payload), encoding="utf-8")
        result = run_cli(bad, self.env)
        self.assertEqual(result.returncode, 2)
        error = json.loads(result.stdout)
        self.assertEqual(error["error"], "profile_invalid")
        self.assertNotIn("etc", result.stdout)

    def test_packaged_inspr_help_lists_readiness_and_legacy_commands(self):
        inspr = os.environ.get("INSPR")
        if not inspr:
            self.skipTest("packaged inspr not supplied")
        help_text = subprocess.check_output([inspr, "--help"], text=True)
        for command in ("check", "heal", "onboard", "post-deploy", "readiness"):
            self.assertIn(command, help_text)
        listed = subprocess.check_output([inspr, "check", "--list"], text=True)
        self.assertIn("nix_on_path", listed)
        self.assertNotIn("NOT YET IMPLEMENTED", help_text)


if __name__ == "__main__":
    unittest.main()
