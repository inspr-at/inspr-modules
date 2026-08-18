#!/usr/bin/env bash
# leak-guard.sh — refuse to publish operator-specific content.
#
# This repository is public. Its private counterpart holds one organisation's
# identity, hosts, trackers and preferences. Nothing from that side may cross.
#
# The guard scans tracked files and fails on any match. It excludes itself,
# since it necessarily contains the patterns it looks for.
set -euo pipefail

SELF="scripts/leak-guard.sh"
CHANGELOG="CHANGELOG.md"
WORKFLOW=".github/workflows/leak-guard.yml"

# Operator identity, infrastructure, trackers, project keys.
#
# Deliberately NOT blocked: the maintainer's GitHub handle. A public repository
# has to name who reviews it, so CODEOWNERS and CONTRIBUTING legitimately carry
# it. What must never cross is contact detail, infrastructure and tracker state
# — an email address, a hostname, a credential path, an issue key.
# Blocking set: credentials, infrastructure, and operator contact detail.
# Deliberately NOT blocked here (unlike a from-scratch public repo):
#   - ticket keys, which appear throughout CHANGELOG as historical provenance
#   - `~/Code/...` citation footnotes in the harvested rule corpus
# Those leak workspace shape, not access, and removing them is a line-by-line
# pass tracked as INSPR-299 slice 4. Tighten this list when that lands.
PATTERNS=(
  'markus@'           '@barta\.'          '[a-z0-9.-]+\.cm\b'
  '~/\.inspr/secrets'
  # NOT blocked: PPMAPIKEY / PAIMOS_API_KEY. Those are variable NAMES and
  # part of this library's documented interface — paimos-config cannot be
  # explained without them. A name is not a credential; a value would be
  # caught by the shape patterns below.
  '(api[_-]?key|token|password|secret)["'"'"' ]*[:=]["'"'"' ]*[A-Za-z0-9/+=_-]{16,}'
  'hsb[0-9]'          'csb[0-9]'          'mbp[0-9]{4}'
  'agm[0-9]'          'dsc[0-9]'          'imac0'
  'pm\.barta'         'paimos\.agm'       'hs\.barta'
)

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
FIXTURE="tests/repository-location-surface.sh"

# Fail closed if we are not in a git repository. Previously this printed
# "clean (0 files scanned)" and exited 0 — a scanner that cannot see anything
# must never report success.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "leak-guard: not inside a git repository — cannot scan, refusing to report clean" >&2
  exit 2
}

# SCOPE: every tracked file. This was previously limited to
# docs/ commands/ AGENTS.md README.md CONTRIBUTING.md while the success message
# printed the count of ALL tracked files — "clean (82 files scanned)" having
# scanned about twelve. That overstatement is how the operator tailnet address
# and identity survived in pkgs/inspr/inspr.sh until INSPR-301.
while IFS= read -r f; do
  [ "$f" = "$SELF" ] && continue
  [ "$f" = "$WORKFLOW" ] && continue
  [ "$f" = "$CHANGELOG" ] && continue   # history, not live guidance
  # The allowlist necessarily quotes the patterns it exempts, so it matches
  # itself. Excluded for the same reason as this script. Caught by CI, not
  # locally: the file was still untracked when tested, so `git ls-files` did
  # not yield it — the tested state differed from the shipped state.
  [ "$f" = "$ALLOWFILE" ] && continue
  # Same reason again: this test asserts that certain deprecated URLs are ABSENT
  # from the shipped surfaces, so it must contain them to check for them. It is
  # exempt structurally rather than by allowlist, because the failure mode is
  # nasty: the day someone tightens PATTERNS, this file false-positives, and the
  # obvious "fix" is to delete the strings — which silently disables the guard
  # the test provides.
  [ "$f" = "$FIXTURE" ] && continue

  # Binary files are scanned for matches but never rendered.
  if [ ! -r "$f" ]; then
    echo "UNREADABLE  $f — cannot scan; failing closed"
    unreadable=1; fail=1; continue
  fi
  scanned=$((scanned+1))

  for p in "${PATTERNS[@]}"; do
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
      echo "LEAK  $f  line(s) $lines  match /$p/"
      fail=1
    fi
  done
done < <(git ls-files)

if [ "$fail" -ne 0 ]; then
  echo
  [ "$unreadable" -ne 0 ] && echo "One or more files could not be read. Fix access before trusting this result."
  echo "Refusing to publish. Move the content to the private doctrine repository,"
  echo "or generalise it so it names no operator, host, tracker or project."
  echo "Matched text is intentionally not shown — open the file at the line above."
  exit 1
fi
echo "leak-guard: clean ($scanned files scanned, $allowed allowlisted match(es) — see $ALLOWFILE)"
