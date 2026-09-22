#!/usr/bin/env bash
# model-role-doctrine — INSPR-463: doctrine names roles, never models.
#
#   bash tests/model-role-doctrine.sh <repo_root>            # doctrine surfaces + lint of this repo
#   bash tests/model-role-doctrine.sh --lint <root> <path>…  # lint only; for consumers (nixcfg etc.)
#
# Concrete model identifiers (vendor ids, product names with versions) may
# appear only in the CHANGELOG and in the design-frontier gauntlet, whose
# Claude lens is *defined* by one exact model (a product decision, not routing).
set -euo pipefail

pattern='gpt-[0-9]+(\.[0-9]+)?-[a-z]+|grok[- ]?[0-9]+\.[0-9]+|claude-(opus|sonnet|haiku|fable)-[0-9]|(^|[^a-z0-9-])(opus|sonnet|haiku|fable)[- ]?[0-9]+(\.[0-9]+)?([^a-z0-9]|$)|composer-[0-9]+\.[0-9]+'

lint() {
  local root=$1; shift
  local hits
  hits=$(cd "$root" && grep -rniE "$pattern" "$@" \
    --exclude=CHANGELOG.md --exclude-dir=design-frontier-gauntlet --exclude-dir=.git 2>/dev/null || true)
  if [[ -n $hits ]]; then
    printf 'model-role-doctrine: concrete model identifiers outside the registry:\n%s\n' "$hits" >&2
    printf 'Name a role and resolve it with `paimos model resolve`; see AGENTS-DOMAIN-DEV.md § model choice by role.\n' >&2
    exit 1
  fi
}

if [[ ${1:-} == --lint ]]; then
  shift; root=$1; shift
  [[ $# -gt 0 ]] || { echo 'model-role-doctrine: --lint needs at least one path' >&2; exit 2; }
  lint "$root" "$@"; printf 'model-role-doctrine: lint ok\n'; exit 0
fi

repo_root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
kernel="$repo_root/docs/AGENTS-KERNEL.md"
mirror="$repo_root/AGENTS.md"
dev="$repo_root/docs/AGENTS-DOMAIN-DEV.md"

fail() { printf 'model-role-doctrine: %s\n' "$*" >&2; exit 1; }

for surface in "$kernel" "$mirror"; do
  grep -Fq -- '**Model choice:**' "$surface" || fail "$surface lacks the model-choice routing rule"
  grep -Fq -- 'paimos model resolve <role>' "$surface" || fail "$surface does not route model choice through the resolver"
  grep -Fq -- 'Never name a concrete model' "$surface" || fail "$surface lacks the no-hardcoded-model rule"
done

grep -Fq -- '## Pattern: model choice by role' "$dev" || fail "DEV pack lacks the model-choice pattern"
for role in scout mechanical build build-hard review-gate; do
  grep -Fq -- "| \`$role\` |" "$dev" || fail "DEV pack rubric lacks role $role"
done
for required in \
  'paimos model resolve <role> [--author-family <yours>]' \
  'Never hardcode a model' \
  'Walk the ladder the resolver prints' \
  'skipping the author'"'"'s family and any route under an active override' \
  'reviewer profile id and version'
do
  grep -Fq -- "$required" "$dev" || fail "DEV pack lacks: $required"
done

for skill in housekeeping product-gauntlet; do
  grep -Fq -- 'paimos model resolve' "$repo_root/skills/$skill/SKILL.md" || fail "skills/$skill does not resolve models by role"
done

lint "$repo_root" docs commands skills README.md AGENTS.md CONTRIBUTING.md SECURITY.md
printf 'model-role-doctrine: ok\n'
