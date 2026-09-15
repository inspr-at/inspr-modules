#!/usr/bin/env bash
# Drift check for a consumer's vendored consent-gate copy (INSPR-431).
#
#   check-consent-gate-vendored.sh <vendored-file> <expected-sha256> [<upstream-file>]
#
# Fails when the vendored bytes differ from the pinned sha256, or, when an
# upstream file is given (for example doctrine/packages/consent-gate/consent-gate.js
# from the vendored inspr-modules submodule), when the copy differs from it.
# Consumers run this in CI next to their other supply-chain pins.
set -euo pipefail
vendored=${1:-}
expected=${2:-}
upstream=${3:-}
if [ -z "$vendored" ] || [ -z "$expected" ]; then
  echo "usage: $0 <vendored-file> <expected-sha256> [<upstream-file>]" >&2
  exit 2
fi
if command -v sha256sum >/dev/null 2>&1; then
  digest() { sha256sum "$1" | awk '{print $1}'; }
else
  digest() { shasum -a 256 "$1" | awk '{print $1}'; }
fi
[ -f "$vendored" ] || { echo "consent-gate: vendored file missing: $vendored" >&2; exit 1; }
actual=$(digest "$vendored")
if [ "$actual" != "$expected" ]; then
  echo "consent-gate: vendored copy differs from the pinned bytes ($actual != $expected); re-copy and re-pin" >&2
  exit 1
fi
if [ -n "$upstream" ]; then
  [ -f "$upstream" ] || { echo "consent-gate: upstream file missing: $upstream" >&2; exit 1; }
  if ! cmp -s "$vendored" "$upstream"; then
    echo "consent-gate: vendored copy differs from the upstream file $upstream; re-copy and re-pin" >&2
    exit 1
  fi
  echo "consent-gate: vendored copy matches pinned bytes and upstream"
else
  echo "consent-gate: vendored copy matches pinned bytes"
fi
