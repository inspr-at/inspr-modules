#!/usr/bin/env bash
# Closed Git-blob import for the routing-edge public slice (INSPR-390).
#
# Reads tracked blobs at a pinned commit from a private INSPR checkout passed
# through INSPR_ROUTING_SOURCE_REPO. Writes only the closed inventory paths
# into this public atelier. Emits import-receipt.json and source-provenance.txt
# with opaque commit ids and digests — no private remote URLs or host paths.
#
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
import_dir="$repo_root/packages/routing-edge/import"
inventory="$import_dir/closed-inventory.json"
receipt="$import_dir/import-receipt.json"
provenance="$import_dir/source-provenance.txt"

source_repo="${INSPR_ROUTING_SOURCE_REPO:-}"
if [[ -z "$source_repo" ]]; then
  printf 'Set INSPR_ROUTING_SOURCE_REPO to a Git checkout of the private INSPR umbrella.\n' >&2
  exit 1
fi
if ! git -C "$source_repo" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'INSPR_ROUTING_SOURCE_REPO is not a Git checkout: %s\n' "$source_repo" >&2
  exit 1
fi

python3 - "$repo_root" "$source_repo" "$inventory" "$receipt" "$provenance" <<'PY'
import hashlib
import json
import os
import subprocess
import sys

repo_root, source_repo, inventory_path, receipt_path, provenance_path = sys.argv[1:6]

with open(inventory_path, encoding="utf-8") as handle:
    inventory = json.load(handle)

if inventory.get("schema") != "inspr-routing-edge-closed-import/0.1":
    raise SystemExit("unexpected closed inventory schema")

commit = inventory.get("source_commit", "")
if len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit):
    raise SystemExit("source_commit must be a 40-character lowercase commit id")

paths = inventory.get("paths")
if not isinstance(paths, list) or len(paths) != 48:
    raise SystemExit(
        f"closed inventory must list exactly 48 paths, got {len(paths) if isinstance(paths, list) else 'non-list'}"
    )
if len(set(paths)) != 48:
    raise SystemExit("closed inventory contains duplicate paths")

allowed_prefixes = ("contracts/routing/", "packages/routing-edge/")
for path in paths:
    if not isinstance(path, str) or not path:
        raise SystemExit(f"invalid inventory path: {path!r}")
    if ".." in path.split("/") or path.startswith("/"):
        raise SystemExit(f"path traversal rejected: {path}")
    if not path.startswith(allowed_prefixes):
        raise SystemExit(f"unknown import prefix: {path}")
    if path.endswith(".gitignore"):
        raise SystemExit(f".gitignore must not be imported: {path}")

def git(args: list[str], *, text: bool = True) -> str:
    return subprocess.check_output(
        ["git", "-C", source_repo, *args],
        text=text,
        stderr=subprocess.PIPE,
    ).strip()

resolved = git(["rev-parse", "--verify", f"{commit}^{{commit}}"])
if resolved != commit:
    raise SystemExit(f"source commit {commit} is not available in the configured checkout")

entries: dict[str, tuple[str, str, str]] = {}
raw = subprocess.check_output(
    ["git", "-C", source_repo, "ls-tree", "-r", "-z", commit, "--", "contracts/routing", "packages/routing-edge"],
)
for record in raw.decode("utf-8").split("\0"):
    if not record:
        continue
    meta, path = record.split("\t", 1)
    mode, obj_type, obj_id = meta.split()
    entries[path] = (mode, obj_type, obj_id)

for path in paths:
    entry = entries.get(path)
    if entry is None:
        raise SystemExit(f"missing source path at pinned commit: {path}")
    mode, obj_type, _obj_id = entry
    if obj_type == "commit" or mode == "120000" or obj_type == "link":
        raise SystemExit(f"symlink or gitlink rejected: {path}")
    if obj_type != "blob":
        raise SystemExit(f"non-blob entry rejected: {path} ({obj_type})")

for path in entries:
    if path.endswith(".gitignore"):
        continue
    if path not in paths:
        raise SystemExit(f"source tree contains path outside closed inventory: {path}")

files = []
for path in sorted(paths):
    blob = subprocess.check_output(
        ["git", "-C", source_repo, "show", f"{commit}:{path}"],
        stderr=subprocess.PIPE,
    )
    meta_line = git(["ls-tree", commit, "--", path])
    meta_parts = meta_line.split()
    if len(meta_parts) < 3 or meta_parts[1] != "blob":
        raise SystemExit(f"expected blob for {path}, got {meta_line!r}")
    digest = hashlib.sha256(blob).hexdigest()
    dest = os.path.join(repo_root, path)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as handle:
        handle.write(blob)
    files.append(
        {
            "path": path,
            "git_blob": meta_parts[2],
            "sha256": digest,
            "size": len(blob),
        }
    )

receipt = {
    "schema": "inspr-routing-edge-import-receipt/0.1",
    "source_commit": commit,
    "file_count": len(files),
    "files": files,
}
with open(receipt_path, "w", encoding="utf-8") as handle:
    json.dump(receipt, handle, indent=2)
    handle.write("\n")

tree_lines = [f"{item['sha256']}  {item['path']}" for item in files]
tree_digest = hashlib.sha256("\n".join(tree_lines).encode("utf-8")).hexdigest()
archive_hasher = hashlib.sha256()
for item in files:
    archive_hasher.update(item["path"].encode("utf-8"))
    archive_hasher.update(b"\0")
    archive_hasher.update(bytes.fromhex(item["sha256"]))
    archive_hasher.update(b"\0")
archive_digest = archive_hasher.hexdigest()

provenance_text = "\n".join(
    [
        "inspr-routing-edge source provenance",
        "schema: inspr-routing-edge-source-provenance/0.1",
        f"private_source_commit: {commit}",
        "imported_file_count: 48",
        f"source_tree_digest: sha256:{tree_digest}",
        f"source_archive_digest: sha256:{archive_digest}",
        "inventory: packages/routing-edge/import/closed-inventory.json",
        "receipt: packages/routing-edge/import/import-receipt.json",
        "note: Opaque commit id and content digests only. No private remote or host paths.",
        "public_adaptations: packages/routing-edge/import/public-adaptations.json",
        "",
    ]
)
with open(provenance_path, "w", encoding="utf-8") as handle:
    handle.write(provenance_text)

print(f"imported {len(files)} files from {commit} into {repo_root}")
print(f"receipt: {receipt_path}")
print(f"provenance: {provenance_path}")
PY
