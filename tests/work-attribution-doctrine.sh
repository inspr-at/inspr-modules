#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
kernel="$repo_root/docs/AGENTS-KERNEL.md"
mirror="$repo_root/AGENTS.md"
core="$repo_root/docs/AGENTS-CORE.md"
gauntlets=(
  "$repo_root/skills/product-gauntlet/SKILL.md"
  "$repo_root/skills/design-frontier-gauntlet/SKILL.md"
)

for surface in "$kernel" "$mirror"; do
  grep -Fq -- 'Ticket first; identify the worker.' "$surface" || {
    printf '%s lacks the always-on ticket-first rule\n' "$surface" >&2
    exit 1
  }
  grep -Fq -- 'I work on this — session: <session-name> (<session-UUID>); role: <builder|reviewer|operator>; started: <ISO-8601>' "$surface" || {
    printf '%s lacks the canonical value-free worker marker\n' "$surface" >&2
    exit 1
  }
done

grep -Fq -- '## Topic: workflow/work-attribution' "$core" || {
  printf 'full doctrine lacks the work-attribution section\n' >&2
  exit 1
}

for requirement in \
  'designated PPM or PMA tracker' \
  'no marker means no material work' \
  'Do not name only the coordinator when a child implements.' \
  'Preserve attribution history' \
  'it never means accepted, approved, merged'; do
  grep -Fq -- "$requirement" "$core" || {
    printf 'full doctrine lacks work-attribution requirement: %s\n' "$requirement" >&2
    exit 1
  }
done

if grep -Fq -- 'create one only when PPM writes are explicitly authorized' "$core"; then
  printf 'legacy opt-in ticket rule contradicts the universal protocol\n' >&2
  exit 1
fi

for gauntlet in "${gauntlets[@]}"; do
  grep -Fq -- 'Before dispatch, write `I work on this' "$gauntlet" || {
    printf '%s does not attribute the actual worker before dispatch\n' "$gauntlet" >&2
    exit 1
  }
  grep -Fq -- 'PPM or PMA, never both' "$gauntlet" || {
    printf '%s does not preserve the single tracker of record\n' "$gauntlet" >&2
    exit 1
  }
done

printf 'work-attribution doctrine verified across kernel, mirror, reference, and dispatching skills\n'
