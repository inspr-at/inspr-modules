#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:-$(cd "$(dirname "$0")/.." && pwd)}
policy="$repo_root/docs/AGENTS-VERSIONING.md"
index="$repo_root/docs/AGENTS-INDEX.md"
readme="$repo_root/README.md"

fail() {
  printf 'calendar-version-doctrine: %s\n' "$*" >&2
  exit 1
}

test -f "$policy" || fail "normative policy is missing"
grep -Fq '[AGENTS-VERSIONING.md](AGENTS-VERSIONING.md)' "$index" \
  || fail "canonical doctrine index does not link the policy"
grep -Fq '[Versioning Doctrine](docs/AGENTS-VERSIONING.md)' "$readme" \
  || fail "repository release policy does not link the gradual default"

for required in \
  'inspr-calendar-v1' \
  'YY.MM.DD' \
  'YY.MM.DD.hh.mm.ss' \
  'All fields are based on **UTC**' \
  'Work already in flight MUST finish under the scheme in force' \
  'MUST NOT be renamed, rewritten, retagged' \
  'release_sequence' \
  'last_legacy_version' \
  'first_calendar_version' \
  'Generic utilities such as `sort -V` are not acceptable' \
  '## Ecosystem exceptions' \
  '## Value-free estate inventory'
do
  grep -Fq "$required" "$policy" || fail "missing normative surface: $required"
done

python3 - <<'PY'
import datetime
import re

pattern = re.compile(
    r"^(?:[0-9]{2})\.(?:0[1-9]|1[0-2])\.(?:0[1-9]|[12][0-9]|3[01])"
    r"(?:\.(?:[01][0-9]|2[0-3])\.(?:[0-5][0-9])\.(?:[0-5][0-9]))?$"
)

def parse(value: str) -> tuple[int, int, int, int, int, int]:
    if pattern.fullmatch(value) is None:
        raise ValueError(value)
    parts = [int(part) for part in value.split(".")]
    if len(parts) == 3:
        parts.extend((0, 0, 0))
    year, month, day, hour, minute, second = parts
    datetime.datetime(2000 + year, month, day, hour, minute, second,
                      tzinfo=datetime.timezone.utc)
    return tuple(parts)

valid = {
    "26.08.31": (26, 8, 31, 0, 0, 0),
    "26.08.31.14.05.09": (26, 8, 31, 14, 5, 9),
    "24.02.29": (24, 2, 29, 0, 0, 0),
    "00.01.01.00.00.00": (0, 1, 1, 0, 0, 0),
    "99.12.31.23.59.59": (99, 12, 31, 23, 59, 59),
}
for value, expected in valid.items():
    actual = parse(value)
    if actual != expected:
        raise SystemExit(f"{value}: expected {expected}, got {actual}")

invalid = (
    "2026.08.31", "26.8.31", "26.02.29", "26.04.31",
    "26.08.31.24.00.00", "26.08.31.12.60.00",
    "26.08.31.12.00", "26.08.31Z", "v26.08.31", " 26.08.31",
)
for value in invalid:
    try:
        parse(value)
    except ValueError:
        continue
    raise SystemExit(f"invalid calendar version accepted: {value}")

ordered = [
    "26.08.31",
    "26.08.31.00.00.01",
    "26.08.31.23.59.59",
    "26.09.01",
]
normalized = [parse(value) for value in ordered]
if normalized != sorted(normalized) or len(set(normalized)) != len(normalized):
    raise SystemExit("normalized calendar ordering is not strict")
PY

printf '%s\n' 'calendar-version-doctrine: ok'
