#!/usr/bin/env bash
# Root-owned actual-source import proof for routing-edge (INSPR-390).
#
# Runs the closed import against the pinned private INSPR checkout, emits a
# deterministic archive into an empty owned output directory, and verifies the
# extracted archive bytes. Does not modify the committed public source tree.
#
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_repo="${INSPR_ROUTING_SOURCE_REPO:-}"

if [[ -z "$source_repo" ]]; then
  printf 'Set INSPR_ROUTING_SOURCE_REPO for actual-source archive proof.\n' >&2
  exit 2
fi

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/inspr-routing-import-proof.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

export INSPR_ROUTING_STAGING_ROOT="$tmpdir/staging"
export INSPR_ROUTING_ARCHIVE_DIR="$tmpdir/archives"
mkdir -p "$INSPR_ROUTING_STAGING_ROOT" "$INSPR_ROUTING_ARCHIVE_DIR"

bash "$repo_root/packages/routing-edge/import/import-from-source.sh"

archive="$(find "$INSPR_ROUTING_ARCHIVE_DIR" -maxdepth 1 -type f -name 'routing-edge-source-*.tar' | head -n 1)"
if [[ -z "$archive" ]]; then
  printf 'expected deterministic archive in %s\n' "$INSPR_ROUTING_ARCHIVE_DIR" >&2
  exit 1
fi

python3 - "$archive" "$tmpdir/staging" <<'PY'
import hashlib
import sys
import tarfile
from pathlib import Path

archive_path = Path(sys.argv[1])
staging_root = Path(sys.argv[2])

with tarfile.open(archive_path, "r") as tar:
    members = [member for member in tar.getmembers() if member.isfile()]
    if len(members) != 48:
        raise SystemExit(f"archive must contain exactly 48 regular files, got {len(members)}")
    for member in members:
        if member.issym() or member.islnk():
            raise SystemExit(f"archive symlink rejected: {member.name}")
        payload = tar.extractfile(member)
        if payload is None:
            raise SystemExit(f"missing archive payload: {member.name}")
        content = payload.read()
        dest = staging_root / member.name
        if not dest.is_file():
            raise SystemExit(f"staging missing extracted file: {member.name}")
        if hashlib.sha256(content).hexdigest() != hashlib.sha256(dest.read_bytes()).hexdigest():
            raise SystemExit(f"archive/staging mismatch: {member.name}")

print(f"actual-source archive proof ok: {archive_path.name}")
print(f"source_archive_sha256: sha256:{hashlib.sha256(archive_path.read_bytes()).hexdigest()}")
PY
