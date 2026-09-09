#!/usr/bin/env bash
# Verify the closed routing-edge import boundary in a clean tree (INSPR-390).
#
# Recomputes tree/receipt/provenance coherence, enforces the closed metadata
# inventory, and checks adapted paths against the pinned source commit.
#
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
boundary="$repo_root/packages/routing-edge/import/boundary.py"

python3 "$boundary" verify --repo-root "$repo_root"

if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bash "$repo_root/scripts/leak-guard.sh" "$repo_root"
else
  printf 'routing-edge-import-surface: leak-guard skipped (no git metadata in this environment)\n' >&2
fi
