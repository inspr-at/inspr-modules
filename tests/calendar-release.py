#!/usr/bin/env python3
"""Calendar release, source archive, consumer pin and rollback gates (INSPR-458).

Fixtures use local Git objects, never commits/tags in the working repository.
Forge publication is a coordinator gate; verify signatures when present.
SPDX-License-Identifier: AGPL-3.0-only
"""

import copy
import datetime as dt
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zlib


ROOT = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
SCRIPT = ROOT / "scripts/reserve-release.py"
spec = importlib.util.spec_from_file_location("release", SCRIPT)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
UTC = dt.timezone.utc
NOW = dt.datetime(2026, 9, 21, 12, 34, 56, tzinfo=UTC)


def initial():
    data = release.read(ROOT / "RELEASE.json")
    # The same suite must pass after a real reservation, without changing it.
    data["version"] = None
    data["release_sequence"] = 0
    data["migration_anchor"]["first_calendar_version"] = None
    data["migration_anchor"]["first_calendar_release_sequence"] = None
    return data


def legacy():
    return {"version_scheme": "legacy", "version": "0.17.0",
            "release_channel": "stable", "release_sequence": 0}


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout


class CalendarRelease(unittest.TestCase):
    def test_repository_source(self):
        release.validate(release.read(ROOT / "RELEASE.json"))

    def test_valid_dates_and_integer_width(self):
        for version in ("260909113550.0.0", "261231235959.0.0", "280229120000.0.0",
                        "100101000000.0.0", "991231235959.0.0"):
            with self.subTest(version=version):
                date = release.calendar_time(version)
                self.assertEqual(date.strftime("%y%m%d%H%M%S") + ".0.0", version)
                self.assertGreater(int(version.split(".")[0]), 2**32)
        self.assertEqual(release.calendar_time("991231235959.0.0").year, 2099)

    def test_invalid_dates_legacy_v1_semver_suffixes(self):
        invalid = (
            "26.09.09", "26.09.09.11.35.50", "26.09.08.17.06", "26.10.31", "5.21.0", "0.17.0",
            "20260909113550.0.0", "2609091135.0.0", "260909113550", "260909113550.0",
            "260909113550.0.1", "260909113550.1.0", "260909113550.0.0-rc1",
            "260909113550.0.0+g39d0b59", "260909240000.0.0", "260909116000.0.0",
            "260909113560.0.0", "260229120000.0.0", "260431120000.0.0", "261131120000.0.0",
            "261301120000.0.0", "260001120000.0.0", "260900120000.0.0", "260932120000.0.0",
            "090909113550.0.0", "000101000000.0.0", "v260909113550.0.0",
            " 260909113550.0.0", "260909113550.0.0 ", "260909113550.0.0\n",
            "+260909113550.0.0", "260909113550.00.0", "260909113550.0.00",
            "260909113550.5.0.0", "260909113550Z.0.0", "２60909113550.0.0", None, 260909113550,
        )
        for version in invalid:
            with self.subTest(version=version), self.assertRaises(ValueError):
                release.calendar_time(version)

    def test_reservation_anchor_and_utc(self):
        pending = initial()
        first = release.next_release(pending, NOW)
        self.assertIsNone(pending["version"])
        self.assertEqual(first["version"], "260921123456.0.0")
        self.assertEqual(first["release_sequence"], 1)
        self.assertEqual(first["migration_anchor"]["first_calendar_version"], first["version"])
        self.assertEqual(first["migration_anchor"]["first_calendar_release_sequence"], 1)
        second = release.next_release(first, NOW + dt.timedelta(seconds=1))
        self.assertEqual(second["release_sequence"], 2)
        self.assertEqual(second["migration_anchor"], first["migration_anchor"])
        local = NOW.astimezone(dt.timezone(dt.timedelta(hours=14)))
        self.assertEqual(release.next_release(pending, local), first)
        for invalid in (NOW.replace(tzinfo=None), NOW.replace(year=2009), NOW.replace(year=2100)):
            with self.assertRaises(ValueError):
                release.next_release(pending, invalid)

    def test_same_second_and_clock_regression(self):
        first = release.next_release(initial(), NOW)
        for now in (NOW, NOW.replace(microsecond=999999), NOW - dt.timedelta(seconds=1)):
            with self.assertRaisesRegex(ValueError, "collision or clock regression"):
                release.next_release(first, now)

    def test_fail_closed_metadata_and_anchor(self):
        first = release.next_release(initial(), NOW)
        for field, bad in (
            ("version_scheme", None), ("version_scheme", "unknown"), ("version_scheme", "legacy"),
            ("version_scheme", "inspr-calendar-v1"), ("version_scheme", [release.SCHEME]),
            ("release_sequence", True), ("release_sequence", 1.0), ("release_sequence", "1"),
            ("release_sequence", -1), ("release_sequence", 0), ("release_sequence", 2),
            ("schema", None), ("schema_version", 2.0), ("release_channel", "preview"),
            ("version", "0.17.0"), ("version", "26.09.21"), ("version", "260921123456.0.0-rc1"),
        ):
            data = copy.deepcopy(first)
            data[field] = bad
            with self.subTest(field=field, bad=bad), self.assertRaises(ValueError):
                release.validate(data)
        for field in first:
            data = copy.deepcopy(first)
            del data[field]
            with self.subTest(missing=field), self.assertRaises(ValueError):
                release.validate(data)
        for field in first["migration_anchor"]:
            data = copy.deepcopy(first)
            del data["migration_anchor"][field]
            with self.subTest(missing_anchor=field), self.assertRaises(ValueError):
                release.validate(data)
        with self.assertRaises(ValueError):
            release.validate(initial(), reserved=True)

    def test_mixed_era_order_uses_anchor_and_sequence(self):
        first = release.next_release(initial(), NOW)
        second = release.next_release(first, NOW + dt.timedelta(seconds=1))
        self.assertEqual(release.compare(legacy(), first, second), -1)
        self.assertEqual(release.compare(first, legacy(), second), 1)
        self.assertEqual(release.compare(first, second, second), -1)
        self.assertEqual(release.compare(first, first, second), 0)
        self.assertEqual(release.compare(legacy(), legacy(), second), 0)
        # Corrupt ordinals must fail, even when a raw-string sort looks plausible.
        bad = copy.deepcopy(second)
        bad["release_sequence"] = 1
        with self.assertRaises(ValueError):
            release.compare(first, bad, second)
        third = release.next_release(second, NOW + dt.timedelta(seconds=2))
        third["release_sequence"] = 2
        with self.assertRaises(ValueError):
            release.compare(second, third, second)
        for field, value in (("version_scheme", None), ("version_scheme", "future"),
                             ("version_scheme", "inspr-calendar-v1"), ("release_channel", None),
                             ("release_sequence", None), ("version", "26.10.31")):
            bad = {**first, field: value}
            with self.subTest(field=field, value=value), self.assertRaises(ValueError):
                release.compare(legacy(), bad, second)
        unmapped = {**legacy(), "version": "0.16.1"}
        with self.assertRaisesRegex(ValueError, "no sequence mapping"):
            release.compare(unmapped, first, second)

    def test_file_reservation_cli_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "RELEASE.json"
            path.write_text(json.dumps(initial()))
            self.assertIn(b"unreserved candidate", run(sys.executable, str(SCRIPT), "--file", str(path), "validate"))
            failed = subprocess.run([sys.executable, str(SCRIPT), "--file", str(path), "show"], capture_output=True)
            self.assertNotEqual(failed.returncode, 0)
            self.assertEqual(failed.stdout, b"")
            # The production CLI has no clock override; it reserves UTC now.
            before = dt.datetime.now(UTC).replace(microsecond=0)
            output = run(sys.executable, str(SCRIPT), "--file", str(path), "reserve")
            after = dt.datetime.now(UTC)
            saved = release.read(path)
            self.assertLessEqual(before, release.calendar_time(saved["version"]))
            self.assertLessEqual(release.calendar_time(saved["version"]), after)
            expected = (f"tag: v{saved['version']}\nchangelog: ## [{saved['version']}] - "
                        f"{release.calendar_time(saved['version']).date()}\nrelease_sequence: 1\n").encode()
            self.assertEqual(output, expected)
            self.assertEqual(run(sys.executable, str(SCRIPT), "--file", str(path), "show"), output)
            original = path.read_bytes()
            clock = type("Clock", (dt.datetime,), {"now": classmethod(lambda cls, tz: release.calendar_time(saved["version"]))})
            with patch.object(release.dt, "datetime", clock), self.assertRaisesRegex(ValueError, "collision"):
                release.reserve(path)
            self.assertEqual(path.read_bytes(), original)
            lock = path.with_name(path.name + ".lock")
            lock.write_text("another reservation")
            with self.assertRaisesRegex(ValueError, "lock exists"):
                release.reserve(path)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(lock.read_text(), "another reservation")
            lock.unlink()
            next_clock = type("Clock", (dt.datetime,), {"now": classmethod(
                lambda cls, tz: release.calendar_time(saved["version"]) + dt.timedelta(seconds=1))})
            with patch.object(release.dt, "datetime", next_clock), \
                    patch.object(release.os, "replace", side_effect=OSError("interrupted")), \
                    self.assertRaises(OSError):
                release.reserve(path)
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual([p.name for p in Path(directory).iterdir()], ["RELEASE.json"])

    def test_ambiguous_json(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "RELEASE.json"
            path.write_text('{"version_scheme":"legacy","version_scheme":"inspr-calendar-v2"}')
            with self.assertRaisesRegex(ValueError, "duplicate"):
                release.read(path)

    def test_source_archive_pin_update_and_exact_rollback(self):
        """Build archives from immutable fixture commits; exercise the real pin checker."""
        first = release.next_release(initial(), NOW)
        second = release.next_release(first, NOW + dt.timedelta(seconds=1))
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "source.git"
            (repo / "objects").mkdir(parents=True)
            (repo / "refs/tags").mkdir(parents=True)
            (repo / "HEAD").write_text("ref: refs/heads/main\n")

            def obj(kind, payload):
                raw = kind.encode() + b" " + str(len(payload)).encode() + b"\0" + payload
                oid = hashlib.sha1(raw).hexdigest()
                path = repo / "objects" / oid[:2] / oid[2:]
                path.parent.mkdir(exist_ok=True)
                path.write_bytes(zlib.compress(raw))
                return oid

            def source_commit(record, parent=None):
                # Source-only release build: real flake/lock bytes plus candidate metadata.
                files = {"flake.nix": (ROOT / "flake.nix").read_bytes(),
                         "flake.lock": (ROOT / "flake.lock").read_bytes()}
                if record["version_scheme"] == release.SCHEME:
                    files["RELEASE.json"] = json.dumps(record).encode()
                tree = obj("tree", b"".join(b"100644 " + name.encode() + b"\0" + bytes.fromhex(obj("blob", payload))
                                           for name, payload in sorted(files.items())))
                # Deliberately unsigned local fixture objects; no git commit/tag commands.
                author = "Release Fixture <fixture@example.invalid> 1790000000 +0000"
                commit = obj("commit", (f"tree {tree}\n" + (f"parent {parent}\n" if parent else "")
                                       + f"author {author}\ncommitter {author}\n\nfixture\n").encode())
                tag = "v" + record["version"]
                tag_oid = obj("tag", f"object {commit}\ntype commit\ntag {tag}\ntagger {author}\n\nfixture\n".encode())
                (repo / "refs/tags" / tag).write_text(tag_oid + "\n")
                return commit, tag

            releases = []
            for record in (legacy(), first, second):
                commit, tag = source_commit(record, releases[-1][1] if releases else None)
                archive = run("git", "--git-dir", str(repo), "archive", "--format=tar", commit)
                self.assertEqual(archive, run("git", "--git-dir", str(repo), "archive", "--format=tar", tag))
                digest = hashlib.sha256(archive).hexdigest()
                with tarfile.open(fileobj=io.BytesIO(archive)) as built:
                    self.assertEqual(built.extractfile("flake.lock").read(), (ROOT / "flake.lock").read_bytes())
                    if record["version_scheme"] == release.SCHEME:
                        release.validate(json.load(built.extractfile("RELEASE.json")), reserved=True)
                releases.append((record, commit, tag, digest))

            consumer = root / "consumer"
            run("git", "init", "-q", str(consumer))
            (consumer / ".gitmodules").write_text('[submodule "doctrine"]\npath = doctrine\nurl = https://github.com/inspr-at/inspr-modules.git\n')
            run("git", "-C", str(consumer), "add", ".gitmodules")

            def pin(commit, lock_commit=None):
                run("git", "-C", str(consumer), "update-index", "--add", "--cacheinfo", "160000", commit, "doctrine")
                lock = {"version": 7, "root": "root", "nodes": {
                    "root": {"inputs": {"inspr-modules": "inspr-modules"}},
                    "inspr-modules": {"locked": {"type": "github", "owner": "inspr-at",
                        "repo": "inspr-modules", "rev": lock_commit or commit}}}}
                (consumer / "flake.lock").write_text(json.dumps(lock))
                return subprocess.run(["bash", str(ROOT / "scripts/doctrine-check.sh"), "--multipath-only"],
                                      cwd=consumer, capture_output=True)

            # Upgrade both pins; a split gitlink/lock must fail before activation.
            for record, commit, tag, digest in releases:
                result = pin(commit)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotEqual(pin(releases[2][1], releases[1][1]).returncode, 0)
            # Roll back across both calendar and legacy boundaries without touching the release ledger.
            ledger = json.dumps(second, sort_keys=True)
            tags_before = run("git", "--git-dir", str(repo), "show-ref", "--tags")
            for record, commit, tag, digest in reversed(releases[:2]):
                self.assertEqual(pin(commit).returncode, 0)
                for reference in (commit, tag):
                    rebuilt = run("git", "--git-dir", str(repo), "archive", "--format=tar", reference)
                    self.assertEqual(hashlib.sha256(rebuilt).hexdigest(), digest)
                self.assertGreater(release.compare(second, record, second), 0)
            self.assertEqual(json.dumps(second, sort_keys=True), ledger)
            self.assertEqual(run("git", "--git-dir", str(repo), "show-ref", "--tags"), tags_before)


if __name__ == "__main__":
    unittest.main(verbosity=2)
