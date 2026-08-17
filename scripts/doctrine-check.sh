#!/usr/bin/env bash
# doctrine-check.sh — verify a consuming repo's doctrine wiring actually resolves.
#
# Every failure this catches is SILENT. A dangling @-ref loads nothing and says
# nothing. A broken command symlink means the command simply does not appear —
# you type it, get nothing, and assume you misremembered the name. A stale pin
# looks identical to a current one.
#
# All four assertions come from INSPR-296, and all four were written *after*
# shipping the bug they describe:
#   1  every @-ref in an auto-loaded file resolves
#   2  every entry in the commands dir is a live symlink
#   3  the doctrine pin is not far behind canonical
#   4  a declared command list, if present, matches what is wired
#
# Run from the root of a consuming repo:
#   ./doctrine/scripts/doctrine-check.sh
#
# Exit 0 clean, 1 on any failure. --warn downgrades to advisory.
set -uo pipefail

WARN=0; [[ "${1:-}" == "--warn" ]] && WARN=1
MAX_BEHIND="${DOCTRINE_MAX_BEHIND:-10}"

red=$'\033[0;31m'; grn=$'\033[0;32m'; yel=$'\033[1;33m'; dim=$'\033[2m'; rst=$'\033[0m'
fail=0
ok()   { printf "  ${grn}✓${rst} %s\n" "$1"; }
bad()  { printf "  ${red}✗${rst} %s\n" "$1"; fail=1; }
skip() { printf "  ${dim}∘ %s${rst}\n" "$1"; }

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "not a git repository root" >&2
  exit 2
}
[[ "$PWD" == "$repo_root" ]] || { echo "not a git repository root" >&2; exit 2; }

# ── 1. @-refs resolve ────────────────────────────────────────────────────────
# @-refs resolve from the REPO ROOT, not from the file. Verified empirically.
loaders=()
for f in CLAUDE.md AGENTS.md AGENTS-*.md; do [[ -f "$f" ]] && loaders+=("$f"); done
if [[ ${#loaders[@]} -eq 0 ]]; then
  skip "no auto-loaded file found"
else
  n=0; broken=0
  for f in "${loaders[@]}"; do
    while read -r ref; do
      [[ -z "$ref" ]] && continue
      n=$((n+1)); t="${ref#@./}"
      [[ -e "$t" ]] || { bad "@-ref does not resolve: $ref (in $f)"; broken=$((broken+1)); }
    done < <(grep -oE '^[[:space:]]*@\./[A-Za-z0-9._/-]*' "$f" 2>/dev/null | sed 's/^[[:space:]]*//')
  done
  [[ $broken -eq 0 ]] && ok "$n @-ref(s) resolve"
fi

# ── 2. commands are live symlinks ────────────────────────────────────────────
cdir=""
for d in .claude/commands +agents/commands; do [[ -d "$d" ]] && cdir="$d" && break; done
if [[ -z "$cdir" ]]; then
  skip "no commands directory"
else
  tot=0; brk=0; reg=0
  for c in "$cdir"/*.md; do
    [[ -e "$c" || -L "$c" ]] || continue
    tot=$((tot+1))
    if [[ ! -e "$c" ]]; then bad "dangling command: $(basename "$c") -> $(readlink "$c")"; brk=$((brk+1));
    elif [[ ! -L "$c" ]]; then bad "command is a COPY, not a symlink: $(basename "$c") — copies drift"; reg=$((reg+1)); fi
  done
  [[ $brk -eq 0 && $reg -eq 0 ]] && ok "$tot command(s), all live symlinks"
fi

# ── 3. pin freshness ─────────────────────────────────────────────────────────
for sm in doctrine doctrine-private; do
  [[ -e "$sm/.git" || -d "$sm" ]] || continue
  [[ -d "$sm" ]] || continue
  entry=$(git ls-tree HEAD "$sm" 2>/dev/null)
  mode=$(printf '%s\n' "$entry" | awk '{print $1}')
  [[ "$mode" == "160000" ]] || { skip "$sm: not a tracked submodule"; continue; }
  pin=$(printf '%s\n' "$entry" | awk '{print $3}')
  if ! git -C "$sm" fetch -q origin 2>/dev/null; then skip "$sm: cannot reach origin, pin not checked"; continue; fi
  behind=$(git -C "$sm" rev-list --count "$pin"..origin/HEAD 2>/dev/null || echo "?")
  if [[ "$behind" == "?" ]]; then skip "$sm: pin not comparable"
  elif [[ "$behind" -gt "$MAX_BEHIND" ]]; then bad "$sm pin is $behind commits behind (max $MAX_BEHIND) — run: git submodule update --remote $sm"
  else ok "$sm pin current ($behind behind)"; fi
done

# ── 4. declared list matches wired ───────────────────────────────────────────
# A declared list is what makes assertion 4 checkable at all; without one there
# is nothing to diff against. See INSPR-296.
decl=$(grep -ohE '^\| `/[a-z-]+`' CLAUDE.md 2>/dev/null | grep -oE '/[a-z-]+' | tr -d '/' | sort -u)
if [[ -z "$decl" ]]; then
  skip "no declared command list in CLAUDE.md (optional; see INSPR-296)"
elif [[ -n "$cdir" ]]; then
  wired=$(cd "$cdir" && ls *.md 2>/dev/null | sed 's/\.md$//' | sort -u)
  only_d=$(comm -23 <(echo "$decl") <(echo "$wired"))
  only_w=$(comm -13 <(echo "$decl") <(echo "$wired"))
  [[ -n "$only_d" ]] && bad "declared but not wired: $(echo "$only_d" | tr '\n' ' ')"
  [[ -n "$only_w" ]] && bad "wired but not declared: $(echo "$only_w" | tr '\n' ' ')"
  [[ -z "$only_d" && -z "$only_w" ]] && ok "declared command list matches what is wired"
fi

echo
if [[ $fail -eq 0 ]]; then echo "${grn}doctrine-check: clean${rst}"; exit 0
elif [[ $WARN -eq 1 ]]; then echo "${yel}doctrine-check: issues above (advisory)${rst}"; exit 0
else echo "${red}doctrine-check: FAILED${rst} — every issue above is invisible at runtime"; exit 1; fi
