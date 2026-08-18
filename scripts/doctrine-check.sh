#!/usr/bin/env bash
# doctrine-check.sh — verify a consuming repo's doctrine wiring actually resolves.
#
# Every failure this catches is SILENT. A dangling @-ref loads nothing and says
# nothing. A broken command symlink means the command simply does not appear —
# you type it, get nothing, and assume you misremembered the name. A stale pin
# looks identical to a current one. Two consumption paths at different
# revisions look fine from either side alone.
#
# Assertions:
#   1  every @-ref in an auto-loaded file resolves
#   2  every entry in the commands dir is a live symlink
#   3  doctrine pins are not far behind canonical
#   4  a declared command list, if present, matches what is wired
#   5  all paths consuming the SAME upstream agree bit-for-bit   (INSPR-300)
#
# Run from the root of a consuming repo:
#   ./doctrine/scripts/doctrine-check.sh
#
# Exit 0 clean, 1 on any failure. --warn downgrades to advisory.
set -uo pipefail

WARN=0; [[ "${1:-}" == "--warn" ]] && WARN=1
# Commit distance measures AGE, not compatibility: one breaking commit matters
# more than ten documentation commits. It is a weak proxy kept because it is
# cheap. Assertion 5 is the strong one. Default lowered from 10 — at 10, a repo
# missing an entire refactor reported as "current" (observed 2026-08-17).
MAX_BEHIND="${DOCTRINE_MAX_BEHIND:-3}"
# Assertion 5 concerns DOCTRINE paths only. A flake.lock legitimately pins the
# same third-party input (nixpkgs, home-manager, …) at several revisions via
# different dependency chains; that is normal and not a doctrine split. Without
# this filter the check drowns in false positives — observed on nixcfg, which
# has ten such duplicate pairs.
DOCTRINE_UPSTREAMS="${DOCTRINE_UPSTREAMS:-inspr-modules|inspr-doctrine-private}"
is_doctrine_upstream() { printf '%s' "$1" | grep -qiE "($DOCTRINE_UPSTREAMS)"; }

red=$'\033[0;31m'; grn=$'\033[0;32m'; yel=$'\033[1;33m'; dim=$'\033[2m'; rst=$'\033[0m'
fail=0
ok()   { printf "  ${grn}✓${rst} %s\n" "$1"; }
bad()  { printf "  ${red}✗${rst} %s\n" "$1"; fail=1; }
skip() { printf "  ${dim}∘ %s${rst}\n" "$1"; }

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "not a git repository root" >&2; exit 2; }
[[ "$PWD" == "$repo_root" ]] || { echo "not a git repository root" >&2; exit 2; }

# Strip HTML comments before scanning for @-refs. Loader files document the
# pattern using example @-refs inside <!-- --> blocks; parsing those as real
# references produced false failures in inspr-modules itself.
strip_comments() { perl -0777 -pe 's/<!--.*?-->//gs' "$1" 2>/dev/null || cat "$1"; }

# ── 1. @-refs resolve ────────────────────────────────────────────────────────
# @-refs resolve from the REPO ROOT, not from the file. Verified empirically.
loaders=()
for f in CLAUDE.md AGENTS.md AGENTS-*.md; do [[ -f "$f" ]] && loaders+=("$f"); done
# Commands can carry @-refs too, and a dangling one there is just as silent.
cdir=""
for d in .claude/commands +agents/commands; do [[ -e "$d" ]] && cdir="$d" && break; done
[[ -n "$cdir" ]] && while IFS= read -r c; do loaders+=("$c"); done \
  < <(find -L "$cdir" -maxdepth 1 -name '*.md' 2>/dev/null)

if [[ ${#loaders[@]} -eq 0 ]]; then
  skip "no auto-loaded file found"
else
  n=0; broken=0
  for f in "${loaders[@]}"; do
    while read -r ref; do
      [[ -z "$ref" ]] && continue
      n=$((n+1)); t="${ref#@./}"
      [[ -e "$t" ]] || { bad "@-ref does not resolve: $ref (in $f)"; broken=$((broken+1)); }
    done < <(strip_comments "$f" | grep -oE '^[[:space:]]*@\./[A-Za-z0-9._/-]*' 2>/dev/null | sed 's/^[[:space:]]*//')
  done
  [[ $broken -eq 0 ]] && ok "$n @-ref(s) resolve"
fi

# ── 2. commands are live symlinks ────────────────────────────────────────────
if [[ -z "$cdir" ]]; then
  skip "no commands directory"
elif [[ -L "$cdir" ]]; then
  # The DIRECTORY is the symlink (nixcfg: .claude/commands -> ../+agents/commands).
  # Files inside are then legitimately regular files; requiring each to be a
  # symlink misreported canonical repo-local commands as drifting copies.
  tgt=$(readlink "$cdir")
  if [[ -d "$cdir/" ]]; then
    ok "$(find -L "$cdir" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ') command(s) via directory symlink -> $tgt"
  else
    bad "commands directory symlink is dangling: $cdir -> $tgt"
  fi
else
  tot=0; brk=0; reg=0
  for c in "$cdir"/*.md; do
    [[ -e "$c" || -L "$c" ]] || continue
    tot=$((tot+1))
    if [[ ! -e "$c" ]]; then bad "dangling command: $(basename "$c") -> $(readlink "$c")"; brk=$((brk+1))
    elif [[ ! -L "$c" ]]; then bad "command is a COPY, not a symlink: $(basename "$c") — copies drift"; reg=$((reg+1)); fi
  done
  [[ $brk -eq 0 && $reg -eq 0 ]] && ok "$tot command(s), all live symlinks"
fi

# ── 3. pin freshness ─────────────────────────────────────────────────────────
# Reads the git INDEX, not HEAD. During a bump the new pin is staged but not
# committed; HEAD then reports the PREVIOUS pin. That is invisible in CI (index
# and HEAD match on a fresh checkout) and wrong for exactly one person — whoever
# is doing the bump, i.e. the only real audience. (INSPR-300.)
declare -a PATHS_UPSTREAM=() PATHS_REV=() PATHS_LABEL=()
for sm in doctrine doctrine-private; do
  [[ -e "$sm" ]] || continue
  # The atelier self-symlinks `doctrine -> .` so its own @-refs resolve; that is
  # a 120000 blob, not a 160000 gitlink, and is not a pin at all.
  if [[ -L "$sm" ]]; then skip "$sm: self-symlink -> $(readlink "$sm"), not a pin"; continue; fi
  entry=$(git ls-files --stage "$sm" 2>/dev/null)
  mode=$(printf '%s\n' "$entry" | awk '{print $1}')
  [[ "$mode" == "160000" ]] || { skip "$sm: not a tracked submodule"; continue; }
  pin=$(printf '%s\n' "$entry" | awk '{print $2}')
  url=$(git config -f .gitmodules --get "submodule.$sm.url" 2>/dev/null)
  up=$(printf '%s' "${url:-unknown}" | sed -E 's#^(git@[^:]+:|https://[^/]+/)##; s/\.git$//')
  if is_doctrine_upstream "$up"; then
    PATHS_UPSTREAM+=("$up"); PATHS_REV+=("$pin"); PATHS_LABEL+=("submodule $sm")
  fi
  if ! git -C "$sm" fetch -q origin 2>/dev/null; then skip "$sm: cannot reach origin, pin not checked"; continue; fi
  behind=$(git -C "$sm" rev-list --count "$pin"..origin/HEAD 2>/dev/null || echo "?")
  if [[ "$behind" == "?" ]]; then skip "$sm: pin not comparable"
  elif [[ "$behind" -gt "$MAX_BEHIND" ]]; then bad "$sm pin is $behind commits behind (max $MAX_BEHIND) — run: git submodule update --remote $sm"
  else ok "$sm pin current ($behind behind)"; fi
done

# flake inputs are a second consumption path with different activation timing
if [[ -f flake.lock ]]; then
  while IFS='|' read -r iname iurl irev; do
    [[ -z "$iname" ]] && continue
    is_doctrine_upstream "$iurl" || continue
    PATHS_UPSTREAM+=("$iurl"); PATHS_REV+=("$irev"); PATHS_LABEL+=("flake input $iname")
  done < <(python3 - <<'PY' 2>/dev/null
import json
try: d=json.load(open("flake.lock"))
except Exception: raise SystemExit
for name,node in d.get("nodes",{}).items():
    l=node.get("locked",{})
    if l.get("type")=="github" and l.get("rev"):
        print(f"{name}|{l.get('owner','')}/{l.get('repo','')}|{l['rev']}")
PY
)
fi

# ── 4. declared list matches wired ───────────────────────────────────────────
decl=$(grep -ohE '^\| `/[a-z-]+`' CLAUDE.md 2>/dev/null | grep -oE '/[a-z-]+' | tr -d '/' | sort -u)
if [[ -z "$decl" ]]; then
  skip "no declared command list in CLAUDE.md (optional; see INSPR-296)"
elif [[ -n "$cdir" ]]; then
  wired=$(find -L "$cdir" -maxdepth 1 -name '*.md' -exec basename {} .md \; 2>/dev/null | sort -u)
  only_d=$(comm -23 <(echo "$decl") <(echo "$wired"))
  only_w=$(comm -13 <(echo "$decl") <(echo "$wired"))
  [[ -n "$only_d" ]] && bad "declared but not wired: $(echo "$only_d" | tr '\n' ' ')"
  [[ -n "$only_w" ]] && bad "wired but not declared: $(echo "$only_w" | tr '\n' ' ')"
  [[ -z "$only_d" && -z "$only_w" ]] && ok "declared command list matches what is wired"
fi

# ── 5. paths to the SAME upstream agree ──────────────────────────────────────
# Equality is per-upstream: a repo may legitimately vendor two DIFFERENT
# upstreams. Only paths resolving to the same one must match.
#
# Why equality and not "both reasonably fresh": the two paths activate at
# different moments. A flake input activates at `nixos-rebuild switch` — what
# the hosts run. A submodule activates at `git checkout` — what agent sessions
# read. Submodule ahead means agents follow rules the hosts do not implement;
# input ahead means hosts run capabilities nobody has read the rules for.
# Resolving a divergence by bumping whichever path is easier silently picks one
# of those two failure modes.
if [[ ${#PATHS_UPSTREAM[@]} -lt 2 ]]; then
  skip "single doctrine consumption path — nothing to cross-check"
else
  declare -A seen=(); split=0
  for i in "${!PATHS_UPSTREAM[@]}"; do
    u="${PATHS_UPSTREAM[$i]}"
    if [[ -n "${seen[$u]:-}" ]]; then
      pr="${seen[$u]%%|*}"; pl="${seen[$u]#*|}"
      if [[ "$pr" != "${PATHS_REV[$i]}" ]]; then
        bad "consumption paths DISAGREE for $u:"
        printf "      %-22s %s\n" "$pl" "${pr:0:12}"
        printf "      %-22s %s\n" "${PATHS_LABEL[$i]}" "${PATHS_REV[$i]:0:12}"
        split=1
      fi
    else
      seen[$u]="${PATHS_REV[$i]}|${PATHS_LABEL[$i]}"
    fi
  done
  [[ $split -eq 0 ]] && ok "${#PATHS_UPSTREAM[@]} consumption path(s), all agreeing per upstream"
fi

echo
if [[ $fail -eq 0 ]]; then echo "${grn}doctrine-check: clean${rst}"; exit 0
elif [[ $WARN -eq 1 ]]; then echo "${yel}doctrine-check: issues above (advisory)${rst}"; exit 0
else echo "${red}doctrine-check: FAILED${rst} — every issue above is invisible at runtime"; exit 1; fi
