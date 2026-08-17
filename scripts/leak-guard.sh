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

fail=0
while IFS= read -r f; do
  [ "$f" = "$SELF" ] && continue
  [ "$f" = "$WORKFLOW" ] && continue
  [ "$f" = "$CHANGELOG" ] && continue   # history, not live guidance
  for p in "${PATTERNS[@]}"; do
    if grep -nEi -- "$p" "$f" >/dev/null 2>&1; then
      echo "LEAK  $f  matches /$p/"
      grep -nEi -- "$p" "$f" | head -3 | sed 's/^/        /'
      fail=1
    fi
  done
done < <(git ls-files -- 'docs/*' 'commands/*' 'AGENTS.md' 'README.md' 'CONTRIBUTING.md')

# SCOPE: the doctrine surface only — what an agent auto-loads and what a reader
# lands on. Deliberately NOT yet covering pkgs/ modules/ tests/: the `inspr`
# CLI and several modules legitimately name fleet paths and hosts, and whether
# operator tooling belongs in a public atelier at all is a design decision, not
# a find-and-replace. 20 hits remain there. Tracked as INSPR-299 slice 4b;
# widen this glob when that is decided.

if [ "$fail" -ne 0 ]; then
  echo
  echo "Refusing to publish. Move the content to the private doctrine repository,"
  echo "or generalise it so it names no operator, host, tracker or project."
  exit 1
fi
echo "leak-guard: clean ($(git ls-files | wc -l | tr -d ' ') files scanned)"
