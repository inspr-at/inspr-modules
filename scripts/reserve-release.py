#!/usr/bin/env python3
"""Offline inspr-modules release reservation; never tags, builds or publishes.

SPDX-License-Identifier: AGPL-3.0-only
"""

import argparse
import copy
import datetime as dt
import json
import os
from pathlib import Path
import re
import sys
import tempfile


SCHEME = "inspr-calendar-v2"
CALENDAR = re.compile(
    r"[1-9][0-9](?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])"
    r"(?:[01][0-9]|2[0-3])(?:[0-5][0-9])(?:[0-5][0-9])\.0\.0"
)


def calendar_time(version):
    if not isinstance(version, str) or not CALENDAR.fullmatch(version):
        raise ValueError("expected canonical YYMMDDhhmmss.0.0 (no v or suffix)")
    fields = [int(version[i:i + 2]) for i in range(0, 12, 2)]
    fields[0] += 2000  # No strptime %y century pivot; the doctrine ends at 2099.
    return dt.datetime(*fields, tzinfo=dt.timezone.utc)


def ordinal(value):
    if type(value) is not int or value < 0:
        raise ValueError("release_sequence must be a non-negative integer")
    return value


def validate(data, *, reserved=False):
    """Validate the sole version source, including its pre-reservation state."""
    if not isinstance(data, dict):
        raise ValueError("release metadata must be an object")
    if data.get("schema") != "inspr.release-coordinate.v2" or type(data.get("schema_version")) is not int or data["schema_version"] != 2:
        raise ValueError("absent or unsupported release schema")
    if data.get("version_scheme") != SCHEME:
        raise ValueError("absent or unsupported version_scheme")
    if data.get("release_channel") != "stable":
        raise ValueError("inspr-modules releases use the stable channel")
    sequence = ordinal(data.get("release_sequence"))
    anchor = data.get("migration_anchor")
    if not isinstance(anchor, dict) or (
        anchor.get("legacy_version_scheme") != "legacy"
        or anchor.get("last_legacy_version") != "0.17.0"
        or type(anchor.get("last_legacy_release_sequence")) is not int
        or anchor["last_legacy_release_sequence"] != 0
    ):
        raise ValueError("migration anchor must retain legacy 0.17.0 at sequence 0")
    if "version" not in data or "first_calendar_version" not in anchor or "first_calendar_release_sequence" not in anchor:
        raise ValueError("version and first-calendar fields must be explicit (null until reserved)")
    if data["version"] is None:
        if reserved or sequence != 0 or anchor["first_calendar_version"] is not None or anchor["first_calendar_release_sequence"] is not None:
            raise ValueError("calendar release has not been reserved, or pending anchor is inconsistent")
        return
    current = calendar_time(data["version"])
    first = calendar_time(anchor["first_calendar_version"])
    if type(anchor["first_calendar_release_sequence"]) is not int or anchor["first_calendar_release_sequence"] != 1:
        raise ValueError("first calendar release must have sequence 1")
    if sequence < 1 or current < first or (sequence == 1) != (current == first):
        raise ValueError("version and release_sequence contradict the migration anchor")


def next_release(data, now):
    validate(data)
    if now.tzinfo is None or now.utcoffset() is None:
        raise ValueError("reservation clock must be timezone-aware")
    now = now.astimezone(dt.timezone.utc).replace(microsecond=0)
    if not 2010 <= now.year <= 2099:
        raise ValueError("reservation year must be 2010–2099")
    version = now.strftime("%y%m%d%H%M%S") + ".0.0"
    calendar_time(version)
    if data["version"] is not None and now <= calendar_time(data["version"]):
        raise ValueError("same-second collision or clock regression; wait for a later UTC second")
    result = copy.deepcopy(data)
    result["version"] = version
    result["release_sequence"] += 1
    if result["migration_anchor"]["first_calendar_version"] is None:
        result["migration_anchor"]["first_calendar_version"] = version
        result["migration_anchor"]["first_calendar_release_sequence"] = result["release_sequence"]
    validate(result, reserved=True)
    return result


def compare(left, right, source):
    """Compare mapped releases; older unmapped legacy pins remain opaque."""
    validate(source, reserved=True)
    anchor = source["migration_anchor"]

    def key(record):
        if not isinstance(record, dict) or record.get("release_channel") != source["release_channel"]:
            raise ValueError("cannot compare absent or different channels")
        scheme = record.get("version_scheme")
        version = record.get("version")
        sequence = ordinal(record.get("release_sequence"))
        if scheme == "legacy":
            if version != anchor["last_legacy_version"] or sequence != anchor["last_legacy_release_sequence"]:
                raise ValueError("legacy release has no sequence mapping in this migration anchor")
            return scheme, tuple(int(part) for part in version.split(".")), sequence
        if scheme != SCHEME:
            raise ValueError("absent or unsupported version_scheme (this repository never released v1)")
        calendar_time(version)
        first = anchor["first_calendar_version"]
        if sequence < 1 or version < first or (sequence == 1) != (version == first):
            raise ValueError("release contradicts the migration anchor")
        return scheme, int(version.split(".")[0]), sequence

    ls, lv, lseq = key(left)
    rs, rv, rseq = key(right)
    ordered = (lseq > rseq) - (lseq < rseq)
    if ls == rs and ((lv > rv) - (lv < rv)) != ordered:
        raise ValueError("within-era version order contradicts release_sequence")
    return ordered


def read(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate release metadata field: " + key)
            result[key] = value
        return result

    return json.loads(path.read_text(), object_pairs_hook=unique)


def reserve(path):
    # A persistent-on-crash exclusive lock fails closed. Different worktrees
    # still require one coordinator serializing the stable release lane.
    lock = path.with_name(path.name + ".lock")
    try:
        fd = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        raise ValueError("reservation lock exists; another writer or interrupted reservation needs inspection") from None
    try:
        os.close(fd)
        result = next_release(read(path), dt.datetime.now(dt.timezone.utc))
        # Same-filesystem replacement keeps readers on complete JSON bytes.
        with tempfile.TemporaryDirectory(prefix=".release-", dir=path.parent) as scratch:
            candidate = Path(scratch) / "RELEASE.json"
            with candidate.open("w") as out:
                json.dump(result, out, indent=2)
                out.write("\n")
                out.flush()
                os.fsync(out.fileno())
            candidate.chmod(path.stat().st_mode & 0o777)
            os.replace(candidate, path)
        return result
    finally:
        lock.unlink()


def show(data):
    validate(data, reserved=True)
    version = data["version"]
    print("tag: v" + version)
    print(f"changelog: ## [{version}] - {calendar_time(version).date().isoformat()}")
    print(f"release_sequence: {data['release_sequence']}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, default=Path(__file__).resolve().parents[1] / "RELEASE.json")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("validate", help="validate metadata; allow the initial null coordinate")
    commands.add_parser("reserve", help="reserve UTC now and atomically update RELEASE.json")
    commands.add_parser("show", help="validate a reserved coordinate and print release labels")
    order = commands.add_parser("compare", help="compare two mapped release JSON records; print -1, 0 or 1")
    order.add_argument("left", type=Path)
    order.add_argument("right", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "reserve":
            show(reserve(args.file))
        else:
            data = read(args.file)
            validate(data)
            if args.command == "show":
                show(data)
            elif args.command == "compare":
                print(compare(read(args.left), read(args.right), data))
            else:
                print("release metadata: ok" + (" (unreserved candidate)" if data["version"] is None else ""))
    except (ValueError, OSError) as error:
        parser.exit(1, f"reserve-release: {error}\n")


if __name__ == "__main__":
    main()
