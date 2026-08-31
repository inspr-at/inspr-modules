#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:?repository root is required}
installed_root=${2:?installed worker-doctrine root is required}

fail() {
  printf 'worker-doctrine-surface: %s\n' "$*" >&2
  exit 1
}

skill="$installed_root/SKILL.md"
attribution="$installed_root/references/AGENTS.md"
versioning="$installed_root/references/AGENTS-VERSIONING.md"

test -f "$skill" || fail 'SKILL.md is missing'
test -f "$attribution" || fail 'worker-attribution reference is missing'
test -f "$versioning" || fail 'calendar-version reference is missing'

cmp -s "$repo_root/AGENTS.md" "$attribution" \
  || fail 'installed worker-attribution mirror drifted from canonical AGENTS.md'
cmp -s "$repo_root/docs/AGENTS-VERSIONING.md" "$versioning" \
  || fail 'installed calendar-version reference drifted from canonical doctrine'

grep -Fq '[Worker attribution](references/AGENTS.md)' "$skill" \
  || fail 'SKILL.md does not link the installed worker-attribution reference'
grep -Fq '[Versioning doctrine](references/AGENTS-VERSIONING.md)' "$skill" \
  || fail 'SKILL.md does not link the installed calendar-version reference'
grep -Fq 'I work on this — session: <session-name> (<session-UUID>); role: <builder|reviewer|operator>; started: <ISO-8601>' "$skill" \
  || fail 'SKILL.md lacks the canonical value-free worker marker'
grep -Fq 'designated PPM or PMA tracker, never both' "$attribution" \
  || fail 'installed attribution reference lost the single tracker of record'
grep -Fq 'inspr-calendar-v1' "$versioning" \
  || fail 'installed versioning reference lost the calendar scheme identifier'
grep -Fq 'Work already in flight MUST finish under the scheme in force' "$versioning" \
  || fail 'installed versioning reference lost the gradual-migration boundary'

printf '%s\n' 'worker-doctrine-surface: ok'
