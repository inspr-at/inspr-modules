#!/usr/bin/env bash
# Verify the closed routing-edge import boundary in a clean tree (INSPR-390).
#
# Asserts inventory/receipt/provenance coherence, rejects widening or stray
# files under the imported trees, and checks adapted paths are declared.
#
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
import_dir="$repo_root/packages/routing-edge/import"
inventory="$import_dir/closed-inventory.json"
receipt="$import_dir/import-receipt.json"
adaptations="$import_dir/public-adaptations.json"
provenance="$import_dir/source-provenance.txt"

python3 - "$repo_root" "$inventory" "$receipt" "$adaptations" "$provenance" <<'PY'
import hashlib
import json
import os
import sys

repo_root, inventory_path, receipt_path, adaptations_path, provenance_path = sys.argv[1:6]

with open(inventory_path, encoding="utf-8") as handle:
    inventory = json.load(handle)
with open(receipt_path, encoding="utf-8") as handle:
    receipt = json.load(handle)
with open(adaptations_path, encoding="utf-8") as handle:
    adaptations = json.load(handle)

paths = inventory["paths"]
if inventory.get("path_count") != 48 or len(paths) != 48:
    raise SystemExit("inventory must declare exactly 48 paths")
if receipt["source_commit"] != inventory["source_commit"]:
    raise SystemExit("receipt source_commit does not match inventory")
if receipt["file_count"] != 48 or len(receipt["files"]) != 48:
    raise SystemExit("receipt must contain exactly 48 files")

receipt_paths = [item["path"] for item in receipt["files"]]
if sorted(receipt_paths) != sorted(paths):
    raise SystemExit("receipt paths do not match inventory")

adapted = {item["path"] for item in adaptations["adapted_paths"]}

for item in receipt["files"]:
    path = item["path"]
    full = os.path.join(repo_root, path)
    if not os.path.isfile(full):
        raise SystemExit(f"missing imported file: {path}")
    with open(full, "rb") as handle:
        actual = hashlib.sha256(handle.read()).hexdigest()
    if path not in adapted and actual != item["sha256"]:
        raise SystemExit(f"unadapted file drift from import receipt: {path}")

allowed_roots = ("contracts/routing", "packages/routing-edge")
for root in allowed_roots:
    abs_root = os.path.join(repo_root, root)
    for dirpath, dirnames, filenames in os.walk(abs_root):
        rel_dir = os.path.relpath(dirpath, repo_root)
        for skip in (".git", "__pycache__"):
            if skip in dirnames:
                dirnames.remove(skip)
        for name in filenames:
            if name.endswith(".pyc"):
                continue
            rel = os.path.join(rel_dir, name)
            if rel.startswith("packages/routing-edge/import/"):
                continue
            if rel not in paths:
                raise SystemExit(f"unexpected file outside closed inventory: {rel}")

with open(provenance_path, encoding="utf-8") as handle:
    text = handle.read()
for forbidden in ("/Users/", "github.com/markus", "git@github.com", "inspr-worktrees"):
    if forbidden in text:
        raise SystemExit(f"provenance contains forbidden identity marker: {forbidden}")

print("routing-edge import surface verified")
PY

if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  bash "$repo_root/scripts/leak-guard.sh" "$repo_root"
else
  printf 'routing-edge-import-surface: leak-guard skipped (no git metadata in this environment)\n'
fi
