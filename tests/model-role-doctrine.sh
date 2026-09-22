#!/usr/bin/env bash
# model-role-doctrine — INSPR-463: doctrine names roles, never models.
#
#   bash tests/model-role-doctrine.sh <repo_root>                 # doctrine surfaces + self-test + lint
#   bash tests/model-role-doctrine.sh --lint <root> [--exempt P]… <path>…   # lint only (consumers)
#   bash tests/model-role-doctrine.sh --self-test                 # fixture check of the pattern
#
# Exemptions are root-relative path prefixes. In repo mode they are exactly
# the CHANGELOG (history) and the files that carry the design-frontier Claude
# lens contract, which is *defined* by one exact model (a product decision,
# not routing). Consumers exempt nothing unless they pass --exempt.
set -euo pipefail

# Always a model reference: vendor ids and versioned product names.
strict='gpt-[0-9][a-z0-9.-]*|grok[- ]?[0-9]+(\.[0-9]+)?|claude-(opus|sonnet|haiku|fable)-[0-9]|composer[- ]?[0-9]+(\.[0-9]+)?'
# Family words need routing context on the same line (Shakespeare's sonnets are fine).
family='(^|[^a-z0-9-])(opus|sonnet|haiku|fable)([- ]?[0-9]+(\.[0-9]+)?)?([^a-z0-9]|$)'
context='claude|anthropic|--model|model[ =:]|xhigh|reasoning|effort|harness|codex|route|reviewer|worker'
# Routing syntax that names a model directly.
routing='(--model|-m)[= ]+[a-z0-9]'

repo_exempt=(CHANGELOG.md
  skills/design-frontier-gauntlet/SKILL.md
  skills/design-frontier-gauntlet/references/lenses.md
  skills/design-frontier-gauntlet/references/run-contract.md
  skills/design-frontier-gauntlet/scripts/build_gallery.py
  skills/design-frontier-gauntlet/scripts/test_build_gallery.py)

die() { printf 'model-role-doctrine: %s\n' "$1" >&2; exit "${2:-1}"; }

# scan <root> <path>… ; prints offending "path:line:text" lines. Exemptions
# come from the EXEMPT array (root-relative prefixes); bash 3.2 has no namerefs.
EXEMPT=()
scan() {
  local root=$1; shift
  local p rc out
  [[ -d $root ]] || die "root is not a directory: $root" 2
  for p in "$@"; do [[ -e "$root/$p" ]] || die "path does not exist: $root/$p" 2; done
  set +e
  out=$(cd "$root" && grep -rniE --exclude-dir=.git "$strict|$family|$routing" -- "$@")
  rc=$?
  set -e
  [[ $rc -le 1 ]] || die "grep failed with status $rc" 2
  local line path text keep
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    path=${line%%:*}; path=${path#./}
    keep=1
    for p in "${EXEMPT[@]+"${EXEMPT[@]}"}"; do
      [[ $path == "$p" || $path == "$p"/* ]] && { keep=0; break; }
    done
    [[ $keep -eq 1 ]] || continue
    text=${line#*:*:}
    if printf '%s' "$text" | grep -qiE "$strict|$routing"; then printf '%s\n' "$line"
    elif printf '%s' "$text" | grep -qiE "$family" && printf '%s' "$text" | grep -qiE "$context"; then printf '%s\n' "$line"
    fi
  done <<< "$out"
}

lint() {
  local hits
  hits=$(scan "$@")
  if [[ -n $hits ]]; then
    printf 'model-role-doctrine: concrete model identifiers outside the registry:\n%s\n' "$hits" >&2
    printf 'Name a role and resolve it with `paimos model resolve`; see AGENTS-DOMAIN-DEV.md § model choice by role.\n' >&2
    return 1
  fi
}

self_test() {
  local d; d=$(mktemp -d); trap 'rm -rf "$d"' RETURN
  EXEMPT=()
  printf '%s\n' 'use gpt-6-astra at xhigh' 'Grok 4.7 via cursor' 'claude-opus-5 please' 'Composer 2.5' \
    'claude --model fable' 'codex exec -m gpt-4.1' 'Opus 5 as reviewer' 'run sonnet at high effort' 'gpt-4o' > "$d/bad.txt"
  printf '%s\n' 'Shakespeare Sonnet 18 is fine' 'the magnum opus of the fleet' 'a haiku about autumn' 'a fable for children' \
    'resolve the review-gate role' 'families: openai, anthropic, xai' > "$d/good.txt"
  local n; n=$(scan "$d" bad.txt | wc -l | tr -d ' ')
  [[ $n -eq 9 ]] || die "self-test: expected 9 flagged lines in bad.txt, got $n"
  n=$(scan "$d" good.txt | wc -l | tr -d ' ')
  [[ $n -eq 0 ]] || die "self-test: false positives in good.txt: $(scan "$d" good.txt)"
  EXEMPT=(bad.txt); n=$(scan "$d" bad.txt good.txt | wc -l | tr -d ' '); EXEMPT=()
  [[ $n -eq 0 ]] || die "self-test: exemption by path did not apply"
  printf 'model-role-doctrine: self-test ok\n'
}

case ${1:-} in
  --self-test) self_test; exit 0 ;;
  --lint)
    shift; root=${1:-}; [[ -n $root ]] || die 'usage: --lint <root> [--exempt <path>]… <path>…' 2; shift
    consumer_exempt=(); paths=()
    while [[ $# -gt 0 ]]; do
      case $1 in
        --exempt) [[ -n ${2:-} ]] || die '--exempt needs a path' 2; consumer_exempt+=("$2"); shift 2 ;;
        *) paths+=("$1"); shift ;;
      esac
    done
    [[ ${#paths[@]} -gt 0 ]] || die 'usage: --lint <root> [--exempt <path>]… <path>…' 2
    EXEMPT=("${consumer_exempt[@]+"${consumer_exempt[@]}"}"); lint "$root" "${paths[@]}"; printf 'model-role-doctrine: lint ok\n'; exit 0 ;;
esac

repo_root=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
kernel="$repo_root/docs/AGENTS-KERNEL.md"
mirror="$repo_root/AGENTS.md"
dev="$repo_root/docs/AGENTS-DOMAIN-DEV.md"

for surface in "$kernel" "$mirror"; do
  grep -Fq -- '**Model choice:**' "$surface" || die "$surface lacks the model-choice routing rule"
  grep -Fq -- 'paimos model resolve <role>' "$surface" || die "$surface does not route model choice through the resolver"
  grep -Fq -- 'never in doctrine, skills or prompts' "$surface" || die "$surface lacks the no-hardcoded-model rule"
  grep -Fq -- 'enumerated in `/dev` § model choice by role' "$surface" || die "$surface does not delegate the lens exception"
done

grep -Fq -- '## Pattern: model choice by role' "$dev" || die "DEV pack lacks the model-choice pattern"
for role in scout mechanical build build-hard review-gate; do
  grep -Fq -- "| \`$role\` |" "$dev" || die "DEV pack rubric lacks role $role"
done
for required in \
  'paimos model resolve <role> [--author-family <yours>]' \
  'Never hardcode a model' \
  'Hand fallback' \
  'MUST run the resolver'"'"'s printed read-only command itself' \
  'Walk the ladder the resolver prints' \
  'skipping the author'"'"'s family and any route under an active override' \
  'reviewer profile id and version'
do
  grep -Fq -- "$required" "$dev" || die "DEV pack lacks: $required"
done
for skill in housekeeping product-gauntlet; do
  grep -Fq -- 'paimos model resolve' "$repo_root/skills/$skill/SKILL.md" || die "skills/$skill does not resolve models by role"
  grep -Fq -- 'hand fallback' "$repo_root/skills/$skill/SKILL.md" || die "skills/$skill lacks the hand fallback"
done
grep -Fq -- "--author-family <the builder's family>" "$repo_root/skills/product-gauntlet/SKILL.md" || die "product-gauntlet must pass the builder's family at review"

for p in "${repo_exempt[@]}"; do [[ -e "$repo_root/$p" ]] || die "exempt path no longer exists (drop it): $p"; done
self_test
EXEMPT=("${repo_exempt[@]}")
lint "$repo_root" docs commands skills README.md AGENTS.md CONTRIBUTING.md SECURITY.md
printf 'model-role-doctrine: ok\n'
