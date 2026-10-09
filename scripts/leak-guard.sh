#!/usr/bin/env bash
# leak-guard.sh — scan tracked working-tree files with redacted diagnostics.
# Generic credential shapes are built in; private operator patterns are supplied
# through LEAK_GUARD_PATTERNS and/or LEAK_GUARD_PATTERNS_FILE (extended regex).
# This is a post-push detector and PR check, not a publication barrier.
set -euo pipefail

SELF="scripts/leak-guard.sh"
PATTERNS=(
  '(api[_-]?key|token|password|secret)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9/+=_-]{16,}'
  # Personal workspace and memory citations do not belong in a public library.
  '~/(Code|\.claude/[^[:space:]]*/memory)(/|[[:space:]])'
  '100\.64\.[0-9]+\.[0-9]+'
)

fail_source() {
  echo "leak-guard: $1; failing closed" >&2
  exit 2
}

# Validate patterns without rendering private regexes or matched content.
add_patterns() {
  local pattern status
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    pattern="${pattern%$'\r'}"
    [[ "$pattern" =~ ^[[:space:]]*($|#) ]] && continue
    status=0
    grep -Ei -- "$pattern" /dev/null >/dev/null 2>&1 || status=$?
    [ "$status" -le 1 ] || fail_source "invalid additional pattern"
    PATTERNS+=("$pattern")
  done
}

# Require invocation at the root: relative tracked paths must identify the
# files actually scanned, rather than a partial or unrelated subtree.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
  fail_source "not inside a git repository — cannot scan"
prefix=$(git rev-parse --show-prefix) || fail_source "cannot determine git root"
[ -z "$prefix" ] || fail_source "run from the git root"

add_patterns <<< "${LEAK_GUARD_PATTERNS:-}"
if [ -n "${LEAK_GUARD_PATTERNS_FILE:-}" ]; then
  [ -f "$LEAK_GUARD_PATTERNS_FILE" ] && [ -r "$LEAK_GUARD_PATTERNS_FILE" ] ||
    fail_source "additional patterns file is unreadable"
  pattern_text=$(cat -- "$LEAK_GUARD_PATTERNS_FILE") ||
    fail_source "cannot read additional patterns file"
  add_patterns <<< "$pattern_text"
fi
scan_set=$(git ls-files) || fail_source "cannot list tracked files"
[ -n "$scan_set" ] || fail_source "empty tracked scan set"

# Substring matching, deliberately not regex: an earlier version escaped the
# pattern into grep and produced "stray \\ before /" warnings with silently
# failing matches.
is_allowed() {
  local file="$1" pat="$2" rp rs
  [ -f "$ALLOWFILE" ] || return 1
  while IFS='|' read -r rp rs _; do
    case "$rp" in ''|'#'*) continue;; esac
    [ "$rp" = "$file" ] || continue
    case "$pat" in *"$rs"*) return 0;; esac
  done < "$ALLOWFILE"
  return 1
}

fail=0
scanned=0
unreadable=0
allowed=0
ALLOWFILE=".leak-guard-allow"

while IFS= read -r f; do
  [ "$f" = "$SELF" ] && continue
  # The allowlist quotes patterns so it cannot scan itself.
  [ "$f" = "$ALLOWFILE" ] && continue

  # Binary files are scanned for matches but never rendered.
  if [ ! -r "$f" ]; then
    echo "UNREADABLE  $f — cannot scan; failing closed"
    unreadable=1; fail=1; continue
  fi
  scanned=$((scanned+1))

  pattern_number=0
  for p in "${PATTERNS[@]}"; do
    pattern_number=$((pattern_number+1))
    # -a treats binary as text so a match is still detected; output is the
    # LINE NUMBER only.
    # `|| true`: grep exits 1 on no-match, and under `set -euo pipefail` that
    # aborts the whole script — it exited 1 with NO output at all, which in CI
    # is indistinguishable from a scanner that found something.
    lines=$(grep -naEi -- "$p" "$f" 2>/dev/null | cut -d: -f1 | head -5 | tr '\n' ' ' || true)
    if [ -n "$lines" ]; then
      # Allowlisted? Every entry carries a reason and is counted, so exclusions
      # stay visible rather than silently shrinking the scan.
      if is_allowed "$f" "$p"; then allowed=$((allowed+1)); continue; fi
      # 🔴 The matched TEXT is deliberately not printed. A leak detector that
      # echoes what it found reproduces the leak into CI logs, terminal
      # scrollback and anywhere those are shipped — and a single long line
      # previously produced ~200 KB of output.
      echo "LEAK  $f  line(s) $lines  pattern $pattern_number"
      fail=1
    fi
  done
done <<< "$scan_set"

[ "$scanned" -gt 0 ] || fail_source "empty scannable file set"

if [ "$fail" -ne 0 ]; then
  echo
  [ "$unreadable" -ne 0 ] && echo "One or more files could not be read. Fix access before trusting this result."
  echo "Refusing to publish. Move the content to the private doctrine repository,"
  echo "or generalise it so it names no operator, host, tracker or project."
  echo "Matched text is intentionally not shown — open the file at the line above."
  exit 1
fi
echo "leak-guard: clean ($scanned files scanned, $allowed allowlisted match(es) — see $ALLOWFILE)"
