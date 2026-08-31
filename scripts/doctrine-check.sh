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
#   ./doctrine/scripts/doctrine-check.sh --multipath-only
#
# --multipath-only runs assertion 5 plus only the index/flake discovery that
# assertion needs. It is intended for a thin consumer-CI gate whose checkout
# may initialize the public doctrine path but not doctrine-private. --warn is
# a full-check adoption mode and cannot be combined with the focused mode.
#
# Exit 0 clean, 1 on any failure. --warn downgrades to advisory.
set -uo pipefail

# Portability: this script must run under macOS's system bash (3.2.57), not just
# a modern nix bash. An earlier revision used `declare -A`, which 3.2 rejects —
# the script then aborted mid-assertion and still exited 0, i.e. a doctrine
# split passed clean. Keep this file free of Bash-4-only constructs
# (associative arrays, `${var^^}`, `readarray`).

WARN=0
MODE="full"
case "$#:${1:-}" in
  0:) ;;
  1:--warn) WARN=1 ;;
  1:--multipath-only) MODE="multipath-only" ;;
  *)
    echo "usage: doctrine-check.sh [--warn | --multipath-only]" >&2
    exit 2
    ;;
esac
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

# Canonical comparison identity for Git remotes. Known github.com transport
# forms and flake `github` owner/repo pairs resolve to lower-case `owner/repo`.
# Every other host remains part of the identity (`host/owner/repo`): matching
# path text on GitLab or an SSH alias does not prove it is the GitHub upstream.
normalize_upstream_identity() {
  local raw kind lower rest authority host path owner repo
  raw="$1"
  kind="$2"
  lower=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')
  if [[ "$kind" == "github" ]]; then
    path="$lower"
    host="github.com"
  elif [[ "$kind" != "git" ]]; then
    return 1
  else
  case "$lower" in
    https://*/*|http://*/*|git://*/*|ssh://*/*|git+ssh://*/*)
      rest="${lower#*://}"
      authority="${rest%%/*}"
      [[ "$authority" != "$rest" ]] || return 1
      path="${rest#*/}"
      host="${authority##*@}"
      host=$(printf '%s' "$host" | sed -E 's/:[0-9]+$//')
      ;;
    github.com:*|*@*:*)
      authority="${lower%%:*}"
      path="${lower#*:}"
      host="${authority##*@}"
      ;;
    github:*)
      path="${lower#github:}"
      host="github.com"
      ;;
    *)
      return 1
      ;;
  esac
  fi

  path="${path#/}"
  path="${path%/}"
  path="${path%.git}"
  case "$path" in
    */*/*|""|*'?'*|*'#'*|*'|'*|*$'\t'*|*$'\n'*) return 1 ;;
  esac
  owner="${path%%/*}"
  repo="${path#*/}"
  [[ -n "$owner" && -n "$repo" && "$owner" != "$repo" ]] || return 1
  [[ "$owner" != "." && "$owner" != ".." && "$repo" != "." && "$repo" != ".." ]] || return 1
  case "$owner$repo" in *[!a-z0-9._-]*) return 1 ;; esac
  if [[ "$host" == "github.com" ]]; then
    printf '%s/%s' "$owner" "$repo"
    return
  fi
  case "$host" in *[!a-z0-9._:-]*) return 1 ;; esac
  printf '%s/%s/%s' "$host" "$owner" "$repo"
}

# Git treats a relative submodule URL as relative to the superproject remote
# repository itself (../foo.git is a sibling of bar.git). Preserve the remote
# transport/authority here; normalize_upstream_identity decides whether that
# authority is github.com or a distinct host.
resolve_relative_git_url() {
  RELATIVE_GIT_URL="$1" BASE_GIT_URL="$2" python3 - <<'PY'
import os
import posixpath
import re
from urllib.parse import urlsplit, urlunsplit

relative = os.environ["RELATIVE_GIT_URL"]
base = os.environ["BASE_GIT_URL"]
if not (relative.startswith("../") or relative.startswith("./")):
    raise SystemExit(1)

parsed = urlsplit(base)
if parsed.scheme:
    if not parsed.netloc or not parsed.path:
        raise SystemExit(1)
    joined = posixpath.normpath(posixpath.join(parsed.path, relative))
    if not joined.startswith("/"):
        joined = "/" + joined
    print(urlunsplit((parsed.scheme, parsed.netloc, joined, "", "")))
    raise SystemExit

scp = re.fullmatch(r"([^/:]+(?:@[^/:]+)?):(.*)", base)
if scp:
    prefix, base_path = scp.groups()
    joined = posixpath.normpath(posixpath.join(base_path, relative))
    print(f"{prefix}:{joined}")
    raise SystemExit

raise SystemExit(1)
PY
}

# Resolve url.*.insteadOf and named-remote aliases exactly as Git would, but do
# not contact the remote. The command must emit exactly one non-empty URL.
resolve_effective_git_url() {
  local raw rows count remote_name named_remote
  raw="$1"
  named_remote=0
  while IFS= read -r remote_name; do
    if [[ "$remote_name" == "$raw" ]]; then
      named_remote=1
      break
    fi
  done < <(git remote 2>/dev/null || true)

  if [[ "$named_remote" -eq 1 ]]; then
    if ! rows=$(git remote get-url --all "$raw" 2>/dev/null); then
      return 1
    fi
  elif ! rows=$(git ls-remote --get-url "$raw" 2>/dev/null); then
    return 1
  fi
  count=$(printf '%s\n' "$rows" | awk 'NF { count++ } END { print count + 0 }')
  [[ "$count" -eq 1 ]] || return 1
  printf '%s' "$rows"
}

# Git's default remote for relative submodule URLs is the current branch's
# tracking remote. `origin` is only the fallback when no tracking remote is
# configured. A local `.` remote has no forge identity for this comparison.
resolve_default_remote_url() {
  local branch remote row remote_count url url_count
  branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  remote=""
  remote_count=0
  if [[ -n "$branch" ]]; then
    while IFS= read -r -d '' row; do
      remote="$row"
      remote_count=$((remote_count+1))
    done < <(git config -z --get-all "branch.$branch.remote" 2>/dev/null || true)
    [[ "$remote_count" -le 1 ]] || return 1
  fi
  [[ -n "$remote" ]] || remote="origin"
  [[ "$remote" != "." ]] || return 1

  url=""
  url_count=0
  while IFS= read -r -d '' row; do
    url="$row"
    url_count=$((url_count+1))
  done < <(git config -z --get-all "remote.$remote.url" 2>/dev/null || true)
  [[ "$url_count" -eq 1 ]] || return 1
  printf '%s' "$url"
}

red=$'\033[0;31m'; grn=$'\033[0;32m'; yel=$'\033[1;33m'; dim=$'\033[2m'; rst=$'\033[0m'
fail=0; unchecked=0
ok()   { printf "  ${grn}✓${rst} %s\n" "$1"; }
bad()  { printf "  ${red}✗${rst} %s\n" "$1"; fail=1; }
skip() { printf "  ${dim}∘ %s${rst}\n" "$1"; }
# Distinct from skip(): the assertion was APPLICABLE but could not be evaluated.
# Reporting that as "clean" is how a stale pin passes with no network.
uncheck() { printf "  ${yel}?${rst} %s\n" "$1"; unchecked=$((unchecked+1)); }

repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "not a git repository root" >&2; exit 2; }
[[ "$PWD" == "$repo_root" ]] || { echo "not a git repository root" >&2; exit 2; }

# Focused assertion-5 path discovery intentionally differs from the legacy
# full check in one way: it reads named gitlinks from the INDEX even when the
# corresponding submodule checkout is absent. Consumer CI can therefore init
# only the public `doctrine` checkout needed to execute this script and still
# compare an indexed `doctrine-private` pin. The default path below is kept
# byte-for-byte in its prior checkout-sensitive form for existing callers.
run_multipath_only() {
  declare -a focused_upstream=() focused_rev=() focused_label=()
  local sm entry row_count mode stage symlink_target pin url up
  local row key path_value matched_section match_count
  local url_count default_remote_url resolved_url effective_url
  local flake_rows record iname iurl irev original_kind original_url original_up
  local i j prev_i split

  for sm in doctrine doctrine-private; do
    if ! entry=$(git ls-files --stage -- "$sm" 2>/dev/null); then
      bad "cannot read Git index for $sm — doctrine consumption paths are unverifiable"
      continue
    fi
    [[ -z "$entry" ]] && continue

    row_count=$(printf '%s\n' "$entry" | awk 'NF { count++ } END { print count + 0 }')
    if [[ "$row_count" -ne 1 ]]; then
      bad "$sm index has $row_count row(s); expected exactly one stage-0 gitlink — resolve the index conflict"
      continue
    fi

    mode=$(printf '%s\n' "$entry" | awk '{print $1}')
    stage=$(printf '%s\n' "$entry" | awk '{print $3}')
    if [[ "$stage" == "0" && "$mode" == "120000" ]]; then
      symlink_target=$(git show ":$sm" 2>/dev/null)
      if [[ "$symlink_target" == "." ]]; then
        skip "$sm: indexed self-symlink -> ., not a pin"
        continue
      fi
    fi
    if [[ "$stage" != "0" || "$mode" != "160000" ]]; then
      bad "$sm index has mode $mode at stage $stage; expected exactly one stage-0 gitlink"
      continue
    fi

    if [[ ! -f .gitmodules ]]; then
      bad "$sm has 0 matching .gitmodules path entries; expected exactly one"
      continue
    fi
    if ! git config -f .gitmodules --list >/dev/null 2>&1; then
      bad ".gitmodules cannot be parsed — $sm upstream is unverifiable"
      continue
    fi
    matched_section=""
    match_count=0
    while IFS= read -r -d '' row; do
      key="${row%%$'\n'*}"
      path_value="${row#*$'\n'}"
      if [[ "$path_value" == "$sm" ]]; then
        matched_section="${key%.path}"
        match_count=$((match_count+1))
      fi
    done < <(git config -z -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
    if [[ "$match_count" -ne 1 ]]; then
      bad "$sm has $match_count matching .gitmodules path entries; expected exactly one"
      continue
    fi

    url=""
    url_count=0
    while IFS= read -r -d '' row; do
      url="$row"
      url_count=$((url_count+1))
    done < <(git config -z -f .gitmodules --get-all "$matched_section.url" 2>/dev/null || true)
    if [[ "$url_count" -ne 1 ]]; then
      bad "$sm .gitmodules section has $url_count URL entries; expected exactly one"
      continue
    fi

    case "$url" in
      ../*|./*)
        if ! default_remote_url=$(resolve_default_remote_url); then
          bad "$sm uses a relative URL but no usable default Git remote exists"
          continue
        fi
        if ! resolved_url=$(resolve_relative_git_url "$url" "$default_remote_url"); then
          bad "$sm relative .gitmodules URL cannot be resolved against the default Git remote"
          continue
        fi
        url="$resolved_url"
        ;;
    esac
    if ! effective_url=$(resolve_effective_git_url "$url"); then
      bad "$sm .gitmodules URL does not resolve to exactly one effective Git URL"
      continue
    fi
    url="$effective_url"
    if ! up=$(normalize_upstream_identity "$url" git); then
      bad "$sm .gitmodules URL cannot be normalized to one upstream identity"
      continue
    fi

    pin=$(printf '%s\n' "$entry" | awk '{print $2}')
    if is_doctrine_upstream "$up"; then
      focused_upstream+=("$up")
      focused_rev+=("$pin")
      focused_label+=("submodule $sm")
    fi
  done

  if [[ -f flake.lock ]]; then
    flake_rows=$(DOCTRINE_UPSTREAMS="$DOCTRINE_UPSTREAMS" python3 - <<'PY'
import json
import os
import re
import subprocess

try:
    with open("flake.lock", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    raise SystemExit(1)

nodes = data.get("nodes", {})
if not isinstance(nodes, dict):
    raise SystemExit(1)

try:
    doctrine_pattern = os.environ["DOCTRINE_UPSTREAMS"]
except KeyError:
    raise SystemExit(1)

def text(value):
    return value if isinstance(value, str) else ""

def relevant(*values):
    for value in values:
        result = subprocess.run(
            ["grep", "-qiE", f"({doctrine_pattern})"],
            input=text(value),
            text=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode == 0:
            return True
        if result.returncode > 1:
            raise SystemExit(1)
    return False

def emit_error():
    print("error|||")

def resolve_input_path(parts, trail=()):
    current = data.get("root")
    if not isinstance(current, str):
        raise ValueError
    for part in parts:
        if not isinstance(part, str) or current in trail:
            raise ValueError
        node = nodes.get(current)
        inputs = node.get("inputs") if isinstance(node, dict) else None
        if not isinstance(inputs, dict) or part not in inputs:
            raise ValueError
        target = inputs[part]
        if isinstance(target, str):
            current = target
        elif isinstance(target, list):
            current = resolve_input_path(target, trail + (current,))
        else:
            raise ValueError
    return current

relevant_ids = set()
relevant_edges = {}
edge_errors = 0
for source_id, node in nodes.items():
    inputs = node.get("inputs") if isinstance(node, dict) else None
    if not isinstance(inputs, dict):
        continue
    for input_name, target in inputs.items():
        follows_relevant = isinstance(target, list) and any(relevant(part) for part in target)
        if not relevant(input_name) and not follows_relevant:
            continue
        try:
            if isinstance(target, str):
                target_id = target
            elif isinstance(target, list):
                target_id = resolve_input_path(target)
            else:
                raise ValueError
            if target_id not in nodes:
                raise ValueError
            relevant_ids.add(target_id)
            relevant_edges.setdefault(source_id, set()).add(target_id)
        except ValueError:
            edge_errors += 1

edge_state = {}

def relevant_edge_cycle(node_id):
    state = edge_state.get(node_id, 0)
    if state == 1:
        return True
    if state == 2:
        return False
    edge_state[node_id] = 1
    for target_id in relevant_edges.get(node_id, ()):
        if relevant_edge_cycle(target_id):
            return True
    edge_state[node_id] = 2
    return False

try:
    if any(relevant_edge_cycle(node_id) for node_id in relevant_edges):
        edge_errors += 1
except RecursionError:
    edge_errors += 1

for _ in range(edge_errors):
    emit_error()

for name, node in nodes.items():
    original_exists = isinstance(node, dict) and "original" in node
    original = node.get("original") if isinstance(node, dict) else None
    original_owner = text(original.get("owner")) if isinstance(original, dict) else ""
    original_repo = text(original.get("repo")) if isinstance(original, dict) else ""
    original_url = text(original.get("url")) if isinstance(original, dict) else ""
    original_mentions_doctrine = relevant(
        original_owner,
        original_repo,
        original_url,
        f"{original_owner}/{original_repo}",
    )

    if not isinstance(node, dict):
        if name in relevant_ids or relevant(name):
            emit_error()
        continue
    locked = node.get("locked")
    if not isinstance(locked, dict):
        if name in relevant_ids or relevant(name) or original_mentions_doctrine:
            emit_error()
        continue

    kind = locked.get("type")
    owner = text(locked.get("owner"))
    repo = text(locked.get("repo"))
    url = text(locked.get("url"))
    rev = text(locked.get("rev"))
    is_relevant = (
        name in relevant_ids
        or relevant(name, owner, repo, url, f"{owner}/{repo}")
        or original_mentions_doctrine
    )
    if not is_relevant:
        continue

    safe_name = re.sub(r"[^A-Za-z0-9._+-]", "_", text(name)) or "doctrine"
    if kind == "github":
        if not owner or not repo or not rev:
            emit_error()
            continue
        raw_identity = f"{owner}/{repo}"
        record_kind = "path-github"
    elif kind == "git":
        if not url or not rev:
            emit_error()
            continue
        raw_identity = url
        record_kind = "path-git"
    else:
        emit_error()
        continue

    original_kind = ""
    original_identity = ""
    if original_exists:
        if not isinstance(original, dict):
            emit_error()
            continue
        if original.get("type") == "github" and original_owner and original_repo:
            original_kind = "github"
            original_identity = f"{original_owner}/{original_repo}"
        elif original.get("type") == "git" and original_url:
            original_kind = "git"
            original_identity = original_url
        else:
            emit_error()
            continue

    unsafe = "\0|\t\r\n"
    if (
        any(char in raw_identity for char in unsafe)
        or any(char in rev for char in unsafe)
        or any(char in original_identity for char in unsafe)
    ):
        emit_error()
        continue
    print(
        f"{record_kind}|{safe_name}|{raw_identity}|{rev}|"
        f"{original_kind}|{original_identity}"
    )
PY
    ) || {
      bad "flake.lock cannot be parsed — doctrine consumption paths are unverifiable"
      flake_rows=""
    }
    while IFS='|' read -r record iname iurl irev original_kind original_url; do
      [[ -z "$record" ]] && continue
      if [[ "$record" == "error" ]]; then
        bad "doctrine-relevant flake node is malformed — identity type/url/rev must be complete"
        continue
      fi
      if [[ "$record" == "path-git" ]]; then
        if ! effective_url=$(resolve_effective_git_url "$iurl"); then
          bad "doctrine-relevant flake Git URL does not resolve to exactly one effective URL"
          continue
        fi
        iurl="$effective_url"
      elif [[ "$record" != "path-github" ]]; then
        bad "doctrine-relevant flake node has an unsupported discovery record"
        continue
      fi
      if [[ "$record" == "path-git" ]]; then
        if ! up=$(normalize_upstream_identity "$iurl" git); then
          bad "doctrine-relevant flake node cannot be normalized to one upstream identity"
          continue
        fi
      elif ! up=$(normalize_upstream_identity "$iurl" github); then
        bad "doctrine-relevant flake node cannot be normalized to one upstream identity"
        continue
      fi
      if [[ -n "$original_kind" ]]; then
        if [[ "$original_kind" == "git" ]]; then
          if ! effective_url=$(resolve_effective_git_url "$original_url"); then
            bad "doctrine-relevant original Git URL does not resolve to exactly one effective URL"
            continue
          fi
          original_url="$effective_url"
        elif [[ "$original_kind" != "github" ]]; then
          bad "doctrine-relevant original metadata has an unsupported identity type"
          continue
        fi
        if ! original_up=$(normalize_upstream_identity "$original_url" "$original_kind"); then
          bad "doctrine-relevant original metadata cannot be normalized"
          continue
        fi
        if [[ "$original_up" != "$up" ]]; then
          bad "original and locked doctrine identities disagree"
          continue
        fi
      fi
      if ! is_doctrine_upstream "$up"; then
        bad "doctrine-relevant flake node resolves outside the configured doctrine upstreams"
        continue
      fi
      focused_upstream+=("$up")
      focused_rev+=("$irev")
      focused_label+=("flake input $iname")
    done <<< "$flake_rows"
  fi

  if [[ ${#focused_upstream[@]} -lt 2 ]]; then
    skip "single doctrine consumption path — nothing to cross-check"
    return
  fi

  split=0
  i=0
  while [[ $i -lt ${#focused_upstream[@]} ]]; do
    prev_i=-1
    j=0
    while [[ $j -lt $i ]]; do
      if [[ "${focused_upstream[$j]}" == "${focused_upstream[$i]}" ]]; then
        prev_i=$j
        break
      fi
      j=$((j+1))
    done
    if [[ $prev_i -ge 0 && "${focused_rev[$prev_i]}" != "${focused_rev[$i]}" ]]; then
      bad "consumption paths DISAGREE for ${focused_upstream[$i]}:"
      printf "      %-22s %.12s\n" "${focused_label[$prev_i]}" "${focused_rev[$prev_i]}"
      printf "      %-22s %.12s\n" "${focused_label[$i]}" "${focused_rev[$i]}"
      printf '%s\n' \
        "      submodule ahead => agents follow rules hosts do not implement;" \
        "      flake input ahead => hosts run capabilities agents have not read."
      split=1
    fi
    i=$((i+1))
  done
  [[ $split -eq 0 ]] && ok "${#focused_upstream[@]} consumption path(s), all agreeing per upstream"
}

if [[ "$MODE" == "multipath-only" ]]; then
  printf '' | grep -E "($DOCTRINE_UPSTREAMS)" >/dev/null 2>&1
  regex_status=$?
  if [[ $regex_status -gt 1 ]]; then
    echo "DOCTRINE_UPSTREAMS is not a valid regular expression" >&2
    exit 2
  fi
  run_multipath_only
  echo
  if [[ $fail -eq 0 ]]; then
    echo "${grn}doctrine-check: clean${rst}"
    exit 0
  fi
  echo "${red}doctrine-check: FAILED${rst} — every issue above is invisible at runtime"
  exit 1
fi

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
for d in .claude/commands +agents/commands; do [[ -e "$d" || -L "$d" ]] && cdir="$d" && break; done
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
  if [[ -L "$sm" ]]; then
    tgt=$(readlink "$sm")
    if [[ "$tgt" == "." || "$(cd "$sm" 2>/dev/null && pwd -P)" == "$repo_root" ]]; then
      skip "$sm: self-symlink -> $tgt, not a pin"
    else
      bad "$sm is a symlink to '$tgt', not a tracked submodule — its revision is unverifiable"
    fi
    continue
  fi
  entry=$(git ls-files --stage "$sm" 2>/dev/null)
  mode=$(printf '%s\n' "$entry" | awk '{print $1}')
  [[ "$mode" == "160000" ]] || { skip "$sm: not a tracked submodule"; continue; }
  pin=$(printf '%s\n' "$entry" | awk '{print $2}')
  url=$(git config -f .gitmodules --get "submodule.$sm.url" 2>/dev/null)
  up=$(printf '%s' "${url:-unknown}" | sed -E 's#^(git@[^:]+:|https://[^/]+/)##; s/\.git$//')
  if is_doctrine_upstream "$up"; then
    PATHS_UPSTREAM+=("$up"); PATHS_REV+=("$pin"); PATHS_LABEL+=("submodule $sm")
  fi
  if ! git -C "$sm" fetch -q origin 2>/dev/null; then uncheck "$sm: cannot reach origin — freshness NOT verified"; continue; fi
  behind=$(git -C "$sm" rev-list --count "$pin"..origin/HEAD 2>/dev/null || echo "?")
  if [[ "$behind" == "?" ]]; then uncheck "$sm: pin not comparable — freshness NOT verified"
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
  split=0; seen_u=""; 
  for i in $(seq 0 $(( ${#PATHS_UPSTREAM[@]} - 1 ))); do
    u="${PATHS_UPSTREAM[$i]}"
    prev_i=-1
    for j in $(seq 0 $(( i - 1 ))); do
      [[ "${PATHS_UPSTREAM[$j]}" == "$u" ]] && { prev_i=$j; break; }
    done
    if [[ $prev_i -ge 0 && "${PATHS_REV[$prev_i]}" != "${PATHS_REV[$i]}" ]]; then
      bad "consumption paths DISAGREE for $u:"
      printf "      %-22s %s\n" "${PATHS_LABEL[$prev_i]}" "${PATHS_REV[$prev_i]:0:12}"
      printf "      %-22s %s\n" "${PATHS_LABEL[$i]}" "${PATHS_REV[$i]:0:12}"
      split=1
    fi
  done
  [[ $split -eq 0 ]] && ok "${#PATHS_UPSTREAM[@]} consumption path(s), all agreeing per upstream"
fi

echo
if [[ $fail -eq 0 && $unchecked -eq 0 ]]; then echo "${grn}doctrine-check: clean${rst}"; exit 0
elif [[ $fail -eq 0 ]]; then
  echo "${yel}doctrine-check: INCOMPLETE${rst} — $unchecked assertion(s) could not be verified"
  [[ "${DOCTRINE_STRICT:-0}" == "1" ]] && exit 1 || exit 0
elif [[ $WARN -eq 1 ]]; then echo "${yel}doctrine-check: issues above (advisory)${rst}"; exit 0
else echo "${red}doctrine-check: FAILED${rst} — every issue above is invisible at runtime"; exit 1; fi
