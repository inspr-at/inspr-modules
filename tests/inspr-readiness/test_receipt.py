# SPDX-License-Identifier: AGPL-3.0-only
"""Adversarial acceptance of exact managed-workspace receipts, not local Git guesses."""
import json
import unittest
from copy import deepcopy
from datetime import timedelta

from readiness.contract import ProfileError, digest_text, parse_profile
from readiness.receipt import validate_receipt
from test_readiness import FakeHost, NOW, base_profile, fixture_binding, fixture_receipt, run_profile


class ReceiptTests(unittest.TestCase):
    def test_old_profile_cannot_claim_exclusive_without_binding(self):
        p = base_profile()
        p.pop("paimos_readiness")
        e = run_profile(p, FakeHost())
        self.assertEqual(e.status, "unavailable")
        self.assertIn("readiness_binding_missing", [c.reason for c in e.checks])

    def test_exclusive_check_cannot_be_optional_or_shared(self):
        for change in ("optional", "shared"):
            p = base_profile()
            if change == "optional":
                p["checks"]["required"].remove("workspace_isolation")
                p["checks"]["optional"].append("workspace_isolation")
            else:
                p["expected"]["workspace_mode"] = "shared"
            with self.assertRaises(ProfileError):
                parse_profile(p)

    def test_receipt_binds_every_native_field(self):
        for key in fixture_binding():
            with self.subTest(field=key):
                host = FakeHost()
                value = host.receipt[key]
                if key == "project_id": replacement = value + 1
                elif key in ("runtime_id", "runtime_generation"): replacement = "44444444-4444-4444-8444-444444444444"
                elif key == "workspace_identity": replacement = "c" * 64
                elif key == "baseline_digest": replacement = "sha256:" + "c" * 64
                elif key == "workspace_mode": replacement = "shared"
                elif key == "account_label": replacement = "chatgpt"
                else: replacement = "different"
                host.receipt[key] = replacement
                self.assertNotEqual(run_profile(base_profile(), host).status, "ready")

    def test_workspace_occupancy_and_server_downgrade_block_ready(self):
        for overall, check in (("needs_setup", "fail"), ("unavailable", "pass"), ("ready", "unknown")):
            host = FakeHost()
            host.receipt["status"] = overall
            host.receipt["checks"][0]["status"] = check
            self.assertNotEqual(run_profile(base_profile(), host).status, "ready")

    def test_missing_producer_and_failed_lookup_block_ready(self):
        for missing in (True, False):
            host = FakeHost()
            if missing: host.which_map.pop("paimos-agentd")
            else: host.receipt_exit = 1
            self.assertEqual(run_profile(base_profile(), host).status, "unavailable")

    def test_local_workspace_identity_is_observed_not_trusted_from_profile(self):
        host = FakeHost()
        host.git_dir = "/fixture/other/.git/worktrees/other"
        self.assertNotEqual(run_profile(base_profile(), host).status, "ready")

    def test_age_is_not_extended_and_each_probe_requeries(self):
        host = FakeHost()
        first = run_profile(base_profile(), host, use_cache=True)
        self.assertEqual(first.status, "ready")
        self.assertEqual(first.expires_at, NOW + timedelta(seconds=60))
        host.receipt["checks"][0]["status"] = "fail"
        host.receipt["status"] = "needs_setup"
        second = run_profile(base_profile(), host, use_cache=True)
        self.assertEqual(second.status, "needs_setup")
        commands = [x for x in host.recorded if x[0].endswith("/paimos-agentd")]
        self.assertEqual(len(commands), 2)
        self.assertTrue(all(x[1] == "readiness-receipt" for x in commands))
        self.assertNotIn("start", [part for command in commands for part in command])

    def test_stale_future_malformed_and_secret_fields_are_closed(self):
        variants = [
            {"expires_at": "2026-09-07T14:45:00Z"},
            {"observed_at": "2026-09-07T14:45:00.001Z"},
            {"observed_at": None}, {"observed_at": "2026-09-07T14:44:50"},
            {"api_key": "synthetic-only"}, {"checks": []},
            {"workspace_identity": "z"*64}, {"next_action": "/private/path"},
        ]
        for change in variants:
            with self.subTest(change=change):
                with self.assertRaises(ProfileError):
                    validate_receipt(json.dumps({**fixture_receipt(), **change}).encode(), fixture_binding(), now=NOW)

    def test_duplicate_wire_fields_are_rejected(self):
        raw = json.dumps(fixture_receipt()).encode()
        raw = b'{"status":"unavailable",' + raw[1:]
        with self.assertRaises(ProfileError):
            validate_receipt(raw, fixture_binding(), now=NOW)

    def test_export_has_no_native_tuple_or_path(self):
        e = run_profile(base_profile(), FakeHost())
        encoded = json.dumps(e.as_dict())
        for value in ("11111111-1111", "22222222-2222", "33333333-3333", "/fixture/", "fixture-worktree", "baseline_digest"):
            self.assertNotIn(value, encoded)


if __name__ == "__main__":
    unittest.main()
