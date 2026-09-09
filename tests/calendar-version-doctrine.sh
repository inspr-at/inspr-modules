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
  'inspr-calendar-v2' \
  'inspr-calendar-v1' \
  'YYMMDDhhmmss.0.0' \
  'YY.MM.DD[.hh.mm.ss]' \
  'There is no short form' \
  'constant `0.0`' \
  'syntactically valid Semantic Versioning 2.0.0' \
  'not** SemVer-semantic' \
  'MUST NOT append a prerelease' \
  '32-bit integer' \
  'All fields are based on **UTC**' \
  'Work already in flight MUST finish under the scheme in force' \
  'MUST NOT be renamed, rewritten, retagged' \
  'MUST NOT patch v1 grammar deviations in place' \
  'immutable, enumerated artifact set' \
  'Immutability applies per artifact coordinate' \
  'outputs MUST NOT be' \
  'exact version, artifact' \
  'release_sequence' \
  'last_legacy_version' \
  'first_calendar_version' \
  'Shape is provably insufficient' \
  'Generic utilities such as `sort -V` are not acceptable' \
  '## Ecosystem exceptions' \
  '## Value-free estate inventory' \
  'trunkver.org'
do
  grep -Fq "$required" "$policy" || fail "missing normative surface: $required"
done

if grep -Fq 'same version MUST NOT identify different bytes' "$policy"; then
  fail "over-broad byte identity would forbid multi-platform release sets"
fi

python3 - <<'PY'
import datetime
import re

# Canonical inspr-calendar-v2 grammar, verbatim from the doctrine.
pattern = re.compile(
    r"^(?:[1-9][0-9])(?:0[1-9]|1[0-2])(?:0[1-9]|[12][0-9]|3[01])"
    r"(?:[01][0-9]|2[0-3])(?:[0-5][0-9])(?:[0-5][0-9])\.0\.0$"
)

# Official SemVer 2.0.0 grammar (semver.org, "Is there a suggested regular
# expression"). Every canonical v2 coordinate MUST match it.
semver = re.compile(
    r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"
    r"(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)"
    r"(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?"
    r"(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$"
)

# Superseded inspr-calendar-v1 grammar; v2 parsers MUST reject it.
legacy_v1 = re.compile(
    r"^(?:[0-9]{2})\.(?:0[1-9]|1[0-2])\.(?:0[1-9]|[12][0-9]|3[01])"
    r"(?:\.(?:[01][0-9]|2[0-3])\.(?:[0-5][0-9])\.(?:[0-5][0-9]))?$"
)

def parse(value: str) -> int:
    if pattern.fullmatch(value) is None:
        raise ValueError(value)
    stamp = value.split(".")[0]
    year, month, day = int(stamp[0:2]), int(stamp[2:4]), int(stamp[4:6])
    hour, minute, second = int(stamp[6:8]), int(stamp[8:10]), int(stamp[10:12])
    datetime.datetime(2000 + year, month, day, hour, minute, second,
                      tzinfo=datetime.timezone.utc)
    return int(stamp)

valid = {
    "260909113550.0.0": 260909113550,
    "261231235959.0.0": 261231235959,
    "280229120000.0.0": 280229120000,
    "100101000000.0.0": 100101000000,
    "991231235959.0.0": 991231235959,
}
for value, expected in valid.items():
    actual = parse(value)
    if actual != expected:
        raise SystemExit(f"{value}: expected {expected}, got {actual}")
    if semver.fullmatch(value) is None:
        raise SystemExit(f"{value}: canonical v2 coordinate is not SemVer-syntactic")
    if legacy_v1.fullmatch(value) is not None:
        raise SystemExit(f"{value}: canonical v2 coordinate matches the v1 grammar")

invalid = (
    "26.09.09", "26.09.09.11.35.50", "26.09.08.17.06",      # v1 and v1-deviant
    "5.21.0", "0.6.0",                                      # SemVer-legacy
    "20260909113550.0.0", "2609091135.0.0", "260909113550",
    "260909113550.0.1", "260909113550.1.0", "260909113550.0",
    "260909113550.0.0-rc1", "260909113550.0.0+g39d0b59",
    "260909240000.0.0", "260909116000.0.0", "260909113560.0.0",
    "260229120000.0.0", "260431120000.0.0", "261301120000.0.0",
    "090909113550.0.0", "000101000000.0.0",
    "v260909113550.0.0", " 260909113550.0.0", "260909113550.0.0 ",
    "260909113550.00.0", "260909113550.0.00",
)
for value in invalid:
    try:
        parse(value)
    except ValueError:
        continue
    raise SystemExit(f"invalid calendar version accepted: {value}")

# v1 strings must still be recognisable as v1 by a v1 parser, so a mixed-era
# reader can discriminate on version_scheme without guessing from shape.
for value in ("26.09.09", "26.09.09.11.35.50"):
    if legacy_v1.fullmatch(value) is None:
        raise SystemExit(f"{value}: v1 example no longer matches the v1 grammar")

ordered = [
    "260909113550.0.0",
    "260909113551.0.0",
    "260909235959.0.0",
    "260910000000.0.0",
    "261001000000.0.0",
    "270101000000.0.0",
]
numeric = [parse(value) for value in ordered]
if numeric != sorted(numeric) or len(set(numeric)) != len(numeric):
    raise SystemExit("numeric calendar ordering is not strict")
if ordered != sorted(ordered):
    raise SystemExit("lexical order of canonical coordinates differs from numeric order")

# SemVer precedence (MAJOR first, numeric) must agree with chronological order.
sem_keys = [tuple(int(part) for part in value.split(".")) for value in ordered]
if sem_keys != sorted(sem_keys):
    raise SystemExit("SemVer precedence of canonical coordinates differs from chronological order")

# Two-digit year keeps canonical v2 strings after a repository's existing v1
# tags under plain string sorting (a human-readable property, not a comparator).
if not ("26.09.09" < "260910000000.0.0" and "26.09.09.11.35.50" < "260910000000.0.0"):
    raise SystemExit("v2 coordinates do not string-sort after existing v1 tags")
PY

printf '%s\n' 'calendar-version-doctrine: ok'
