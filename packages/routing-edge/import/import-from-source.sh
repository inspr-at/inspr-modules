#!/usr/bin/env bash
# Closed Git-blob import for the routing-edge public slice (INSPR-390).
#
# Requires:
#   INSPR_ROUTING_SOURCE_REPO  private INSPR checkout with pinned commit
#   INSPR_ROUTING_STAGING_ROOT empty directory for extracted source (not the public tree)
#   INSPR_ROUTING_ARCHIVE_DIR  empty directory for the deterministic source archive bytes
#
# Updates only import metadata (receipt + provenance) in this repo. It never
# writes directly over the committed public source tree.
#
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
import_dir="$repo_root/packages/routing-edge/import"

source_repo="${INSPR_ROUTING_SOURCE_REPO:-}"
staging_root="${INSPR_ROUTING_STAGING_ROOT:-}"
archive_dir="${INSPR_ROUTING_ARCHIVE_DIR:-}"

if [[ -z "$source_repo" ]]; then
  printf 'Set INSPR_ROUTING_SOURCE_REPO to a Git checkout of the private INSPR umbrella.\n' >&2
  exit 1
fi
if [[ -z "$staging_root" || -z "$archive_dir" ]]; then
  printf 'Set INSPR_ROUTING_STAGING_ROOT and INSPR_ROUTING_ARCHIVE_DIR to empty output directories.\n' >&2
  exit 1
fi
if ! git -C "$source_repo" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'INSPR_ROUTING_SOURCE_REPO is not a Git checkout: %s\n' "$source_repo" >&2
  exit 1
fi

python3 "$import_dir/boundary.py" import \
  --source-repo "$source_repo" \
  --staging-root "$staging_root" \
  --archive-dir "$archive_dir" \
  --metadata-dir "$import_dir" \
  --inventory "$import_dir/closed-inventory.json"
