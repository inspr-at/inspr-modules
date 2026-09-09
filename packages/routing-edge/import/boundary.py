#!/usr/bin/env python3
# Closed Git-blob import boundary for routing-edge (INSPR-390).
#
# SPDX-License-Identifier: AGPL-3.0-only
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import stat
import subprocess
import sys
import tarfile
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

INVENTORY_SCHEMA = "inspr-routing-edge-closed-import/0.1"
RECEIPT_SCHEMA = "inspr-routing-edge-import-receipt/0.2"
PROVENANCE_SCHEMA = "inspr-routing-edge-source-provenance/0.2"
ADAPTATIONS_SCHEMA = "inspr-routing-edge-public-adaptations/0.1"
METADATA_INVENTORY_SCHEMA = "inspr-routing-edge-import-metadata-inventory/0.1"
ARCHIVE_FORMAT = "gnu-ustar-deterministic-v1"
ARCHIVE_MTIME = 0
DEFAULT_FILE_MODE = 0o100644
ALLOWED_PREFIXES = ("contracts/routing/", "packages/routing-edge/")


@dataclass(frozen=True)
class FileRecord:
    path: str
    git_blob: str
    sha256: str
    size: int
    content: bytes
    mode: int = DEFAULT_FILE_MODE


@dataclass(frozen=True)
class ImportResult:
    source_commit: str
    staging_root: Path
    archive_path: Path
    tree_digest: str
    archive_sha256: str
    file_count: int


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def load_json(path: Path) -> object:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def validate_path_entry(path: str) -> None:
    if not isinstance(path, str) or not path:
        raise ValueError(f"invalid inventory path: {path!r}")
    if path.startswith("/") or ".." in path.split("/"):
        raise ValueError(f"path traversal rejected: {path}")
    if not path.startswith(ALLOWED_PREFIXES):
        raise ValueError(f"unknown import prefix: {path}")
    if path.endswith(".gitignore"):
        raise ValueError(f".gitignore must not be imported: {path}")


def validate_inventory(inventory: dict) -> list[str]:
    if inventory.get("schema") != INVENTORY_SCHEMA:
        raise ValueError("unexpected closed inventory schema")
    commit = inventory.get("source_commit", "")
    if len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit):
        raise ValueError("source_commit must be a 40-character lowercase commit id")
    paths = inventory.get("paths")
    if not isinstance(paths, list):
        raise ValueError(f"closed inventory must list exactly 48 paths, got non-list")
    if len(set(paths)) != len(paths):
        raise ValueError("closed inventory contains duplicate paths")
    if len(paths) != 48:
        raise ValueError(f"closed inventory must list exactly 48 paths, got {len(paths)}")
    for path in paths:
        validate_path_entry(path)
    return list(paths)


def validate_metadata_inventory(metadata: dict) -> list[str]:
    if metadata.get("schema") != METADATA_INVENTORY_SCHEMA:
        raise ValueError("unexpected metadata inventory schema")
    paths = metadata.get("paths")
    if not isinstance(paths, list) or len(paths) != metadata.get("path_count"):
        raise ValueError("metadata inventory path_count mismatch")
    if len(set(paths)) != len(paths):
        raise ValueError("metadata inventory contains duplicate paths")
    for path in paths:
        if not isinstance(path, str) or not path.startswith("packages/routing-edge/import/"):
            raise ValueError(f"invalid metadata inventory path: {path!r}")
    return list(paths)


def compute_tree_digest(files: Sequence[FileRecord]) -> str:
    lines = [f"{item.sha256}  {item.path}" for item in sorted(files, key=lambda item: item.path)]
    return _sha256_bytes("\n".join(lines).encode("utf-8"))


def git_run(source_repo: Path, args: list[str], *, text: bool = True) -> str | bytes:
    output = subprocess.check_output(
        ["git", "-C", str(source_repo), *args],
        stderr=subprocess.PIPE,
    )
    return output.decode("utf-8").strip() if text else output


def git_read_closed_slice(source_repo: Path, commit: str, paths: Sequence[str]) -> list[FileRecord]:
    resolved = git_run(source_repo, ["rev-parse", "--verify", f"{commit}^{{commit}}"])
    if resolved != commit:
        raise ValueError(f"source commit {commit} is not available in the configured checkout")

    entries: dict[str, tuple[str, str, str]] = {}
    raw = git_run(
        source_repo,
        ["ls-tree", "-r", "-z", commit, "--", "contracts/routing", "packages/routing-edge"],
        text=False,
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
            raise ValueError(f"missing source path at pinned commit: {path}")
        mode, obj_type, obj_id = entry
        if obj_type == "commit" or mode == "120000" or obj_type == "link":
            raise ValueError(f"symlink or gitlink rejected: {path}")
        if obj_type != "blob":
            raise ValueError(f"non-blob entry rejected: {path} ({obj_type})")

    for path in entries:
        if path.endswith(".gitignore"):
            continue
        if path not in paths:
            raise ValueError(f"source tree contains path outside closed inventory: {path}")

    files: list[FileRecord] = []
    for path in sorted(paths):
        content = git_run(source_repo, ["show", f"{commit}:{path}"], text=False)
        if not isinstance(content, bytes):
            raise TypeError("git show must return bytes")
        meta_parts = git_run(source_repo, ["ls-tree", commit, "--", path]).split()
        if len(meta_parts) < 3 or meta_parts[1] != "blob":
            raise ValueError(f"expected blob for {path}, got {meta_parts!r}")
        files.append(
            FileRecord(
                path=path,
                git_blob=meta_parts[2],
                sha256=_sha256_bytes(content),
                size=len(content),
                content=content,
                mode=int(meta_parts[0], 8),
            )
        )
    return files


def ensure_empty_output_root(root: Path, *, label: str) -> None:
    if root.is_symlink():
        raise ValueError(f"{label} must not be a symlink: {root}")
    if root.exists():
        if not root.is_dir():
            raise ValueError(f"{label} must be a directory: {root}")
        if any(root.iterdir()):
            raise ValueError(f"{label} must be empty: {root}")
    else:
        root.mkdir(parents=True, exist_ok=True)
    if root.is_symlink():
        raise ValueError(f"{label} resolved to a symlink: {root}")


def _reject_symlink_ancestor(path: Path, *, within: Path) -> None:
    within = within.resolve()
    try:
        relative = path.relative_to(within)
    except ValueError:
        return
    accum = within
    for part in relative.parts:
        accum = accum / part
        if accum.is_symlink():
            raise ValueError(f"refusing to write through symlink ancestor: {accum}")


def materialize_files(root: Path, files: Sequence[FileRecord]) -> None:
    root = root.resolve()
    ensure_empty_output_root(root, label="staging root")
    for item in files:
        if Path(item.path).is_absolute() or ".." in Path(item.path).parts:
            raise ValueError(f"path traversal rejected: {item.path}")
        dest = root / item.path
        _reject_symlink_ancestor(dest, within=root)
        dest.parent.mkdir(parents=True, exist_ok=True)
        _reject_symlink_ancestor(dest, within=root)
        if dest.exists() and dest.is_symlink():
            raise ValueError(f"destination symlink rejected: {dest}")
        dest.write_bytes(item.content)
        if not dest.is_file() or dest.is_symlink():
            raise ValueError(f"expected regular file after write: {dest}")
        if not str(dest.resolve()).startswith(str(root) + os.sep):
            raise ValueError(f"path escapes staging root: {item.path}")
        os.chmod(dest, stat.S_IMODE(item.mode))


def build_gnu_deterministic_tar(archive_path: Path, files: Sequence[FileRecord]) -> None:
    ensure_empty_output_root(archive_path.parent, label="archive output directory")
    if archive_path.exists():
        raise ValueError(f"archive path already exists: {archive_path}")
    with tarfile.open(archive_path, mode="w", format=tarfile.GNU_FORMAT) as tar:
        for item in sorted(files, key=lambda entry: entry.path):
            info = tarfile.TarInfo(name=item.path)
            info.size = item.size
            info.mtime = ARCHIVE_MTIME
            info.uid = 0
            info.gid = 0
            info.uname = ""
            info.gname = ""
            info.mode = item.mode
            info.type = tarfile.REGTYPE
            tar.addfile(info, io.BytesIO(item.content))


def verify_tar_archive(archive_path: Path, files: Sequence[FileRecord]) -> None:
    expected = {item.path: item for item in files}
    with tarfile.open(archive_path, mode="r") as tar:
        members = tar.getmembers()
        if len(members) != len(expected):
            raise ValueError(
                f"archive must contain exactly {len(expected)} entries, got {len(members)}"
            )
        seen: set[str] = set()
        for member in sorted(members, key=lambda entry: entry.name):
            if member.issym() or member.islnk() or member.isdev() or member.isdir():
                raise ValueError(f"archive entry must be a regular file: {member.name}")
            if member.name in seen:
                raise ValueError(f"duplicate archive path: {member.name}")
            seen.add(member.name)
            if member.name not in expected:
                raise ValueError(f"unexpected archive path: {member.name}")
            item = expected[member.name]
            if stat.S_IMODE(member.mode) != stat.S_IMODE(item.mode):
                raise ValueError(f"mode mismatch for {member.name}")
            payload = tar.extractfile(member)
            if payload is None:
                raise ValueError(f"could not read archive member: {member.name}")
            content = payload.read()
            if _sha256_bytes(content) != item.sha256:
                raise ValueError(f"content mismatch for {member.name}")
        if seen != set(expected):
            raise ValueError("archive is missing expected paths")


def archive_filename(commit: str) -> str:
    return f"routing-edge-source-{commit[:8]}.tar"


def write_receipt(path: Path, *, commit: str, files: Sequence[FileRecord], archive_path: Path) -> None:
    payload = {
        "schema": RECEIPT_SCHEMA,
        "source_commit": commit,
        "file_count": len(files),
        "files": [
            {
                "path": item.path,
                "git_blob": item.git_blob,
                "sha256": item.sha256,
                "size": item.size,
                "mode": oct(item.mode),
            }
            for item in sorted(files, key=lambda entry: entry.path)
        ],
        "archive": {
            "format": ARCHIVE_FORMAT,
            "filename": archive_path.name,
            "sha256": _sha256_file(archive_path),
            "size": archive_path.stat().st_size,
        },
        "tree_digest": f"sha256:{compute_tree_digest(files)}",
    }
    with path.open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def write_provenance(
    path: Path,
    *,
    commit: str,
    tree_digest: str,
    archive_sha256: str,
    archive_name: str,
) -> None:
    lines = [
        "inspr-routing-edge source provenance",
        f"schema: {PROVENANCE_SCHEMA}",
        f"private_source_commit: {commit}",
        "imported_file_count: 48",
        f"source_tree_digest: sha256:{tree_digest}",
        f"source_archive_sha256: sha256:{archive_sha256}",
        f"archive_format: {ARCHIVE_FORMAT}",
        f"archive_filename: {archive_name}",
        "archive_shipped_in_public_repo: false",
        "archive_attestation_note: Public verification recomputes the tree digest and receipt file digests. Archive byte proof runs only during import against the pinned private git blobs.",
        "inventory: packages/routing-edge/import/closed-inventory.json",
        "metadata_inventory: packages/routing-edge/import/metadata-inventory.json",
        "receipt: packages/routing-edge/import/import-receipt.json",
        "public_adaptations: packages/routing-edge/import/public-adaptations.json",
        "note: Opaque commit ids and digests only. No private remote or host paths.",
        "",
    ]
    path.write_text("\n".join(lines), encoding="utf-8")


def parse_provenance(text: str) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for line in text.splitlines():
        if not line.strip() or line.startswith("inspr-routing-edge source provenance"):
            continue
        if ": " not in line:
            continue
        key, value = line.split(": ", 1)
        parsed[key] = value
    return parsed


def load_receipt_records(receipt: dict) -> tuple[str, list[dict], dict]:
    if receipt.get("schema") != RECEIPT_SCHEMA:
        raise ValueError("import receipt schema mismatch")
    commit = receipt["source_commit"]
    files = receipt["files"]
    archive = receipt["archive"]
    if receipt.get("file_count") != 48 or len(files) != 48:
        raise ValueError("receipt must contain exactly 48 files")
    return commit, files, archive


def verify_public_boundary(repo_root: Path) -> None:
    import_dir = repo_root / "packages/routing-edge/import"
    inventory = load_json(import_dir / "closed-inventory.json")
    metadata_inventory = load_json(import_dir / "metadata-inventory.json")
    receipt = load_json(import_dir / "import-receipt.json")
    adaptations = load_json(import_dir / "public-adaptations.json")
    provenance_text = (import_dir / "source-provenance.txt").read_text(encoding="utf-8")

    paths = validate_inventory(inventory)
    metadata_paths = validate_metadata_inventory(metadata_inventory)

    receipt_commit, receipt_files, archive_meta = load_receipt_records(receipt)
    if receipt_commit != inventory["source_commit"]:
        raise ValueError("receipt source_commit does not match inventory")

    if adaptations.get("schema") != ADAPTATIONS_SCHEMA:
        raise ValueError("public adaptations schema mismatch")
    if adaptations.get("source_commit") != inventory["source_commit"]:
        raise ValueError("public adaptations source_commit does not match inventory")

    adapted_entries = adaptations.get("adapted_paths")
    if not isinstance(adapted_entries, list) or not adapted_entries:
        raise ValueError("public adaptations must be a non-empty list")
    adapted: set[str] = set()
    for item in adapted_entries:
        if not isinstance(item, dict) or set(item) != {"path", "reason"}:
            raise ValueError("each public adaptation must contain only path and reason")
        path = item["path"]
        reason = item["reason"]
        if not isinstance(path, str) or path in adapted:
            raise ValueError(f"duplicate or invalid adapted path: {path!r}")
        if not isinstance(reason, str) or len(reason.strip()) < 20:
            raise ValueError(f"adaptation reason is missing or too vague: {path}")
        adapted.add(path)
    if not adapted.issubset(set(paths)):
        raise ValueError("adapted path is outside the closed 48-file inventory")

    receipt_paths = [item["path"] for item in receipt_files]
    if sorted(receipt_paths) != sorted(paths):
        raise ValueError("receipt paths do not match inventory")

    records = [
        FileRecord(
            path=item["path"],
            git_blob=item["git_blob"],
            sha256=item["sha256"],
            size=item["size"],
            content=b"",
            mode=int(item["mode"], 8),
        )
        for item in receipt_files
    ]
    recomputed_tree = compute_tree_digest(records)
    if receipt.get("tree_digest") != f"sha256:{recomputed_tree}":
        raise ValueError("receipt tree_digest does not recompute from file records")

    provenance = parse_provenance(provenance_text)
    if provenance.get("schema") != PROVENANCE_SCHEMA:
        raise ValueError("provenance schema mismatch")
    if provenance.get("private_source_commit") != inventory["source_commit"]:
        raise ValueError("provenance source commit mismatch")
    if provenance.get("source_tree_digest") != f"sha256:{recomputed_tree}":
        raise ValueError("provenance tree digest does not recompute from receipt")
    if provenance.get("source_archive_sha256") != f"sha256:{archive_meta['sha256']}":
        raise ValueError("provenance archive sha256 does not match receipt archive attestation")
    if provenance.get("archive_shipped_in_public_repo") != "false":
        raise ValueError("provenance must declare archive_shipped_in_public_repo: false")
    if archive_meta.get("format") != ARCHIVE_FORMAT:
        raise ValueError("receipt archive format mismatch")

    forbidden = ("/Users/", "github.com/markus", "git@github.com", "inspr-worktrees")
    for marker in forbidden:
        if marker in provenance_text:
            raise ValueError(f"provenance contains forbidden identity marker: {marker}")

    for meta_path in metadata_paths:
        full = repo_root / meta_path
        if full.is_symlink() or not full.is_file():
            raise ValueError(f"metadata inventory path missing or not a regular file: {meta_path}")

    actual_metadata: set[str] = set()
    for entry in import_dir.iterdir():
        if entry.name in {"__pycache__"}:
            continue
        if entry.is_symlink() or not entry.is_file():
            raise ValueError(f"import metadata must be regular files only: {entry.name}")
        rel = str(entry.relative_to(repo_root))
        actual_metadata.add(rel)
    if actual_metadata != set(metadata_paths):
        raise ValueError(
            "import metadata inventory mismatch: "
            f"expected {sorted(metadata_paths)}, got {sorted(actual_metadata)}"
        )

    allowed_roots = ("contracts/routing", "packages/routing-edge")
    for root_name in allowed_roots:
        abs_root = repo_root / root_name
        for dirpath, dirnames, filenames in os.walk(abs_root):
            dirnames[:] = [name for name in dirnames if name not in {".git", "__pycache__"}]
            rel_dir = Path(dirpath).relative_to(repo_root)
            for name in filenames:
                if name.endswith(".pyc"):
                    continue
                rel = str(rel_dir / name)
                if rel.startswith("packages/routing-edge/import/"):
                    continue
                if rel not in paths:
                    raise ValueError(f"unexpected file outside closed inventory: {rel}")
                full = repo_root / rel
                if full.is_symlink() or not full.is_file():
                    raise ValueError(f"imported source path must be a regular file: {rel}")

    for item in receipt_files:
        path = item["path"]
        full = repo_root / path
        if full.is_symlink() or not full.is_file():
            raise ValueError(f"missing imported file: {path}")
        actual = _sha256_file(full)
        if path not in adapted and actual != item["sha256"]:
            raise ValueError(f"unadapted file drift from import receipt: {path}")


def run_import(
    *,
    source_repo: Path,
    staging_root: Path,
    archive_dir: Path,
    metadata_dir: Path,
    inventory_path: Path,
) -> ImportResult:
    inventory = load_json(inventory_path)
    paths = validate_inventory(inventory)
    commit = inventory["source_commit"]
    files = git_read_closed_slice(source_repo, commit, paths)

    ensure_empty_output_root(staging_root, label="staging root")
    ensure_empty_output_root(archive_dir, label="archive output directory")
    materialize_files(staging_root, files)

    archive_path = archive_dir / archive_filename(commit)
    build_gnu_deterministic_tar(archive_path, files)
    verify_tar_archive(archive_path, files)

    tree_digest = compute_tree_digest(files)
    archive_sha256 = _sha256_file(archive_path)

    write_receipt(metadata_dir / "import-receipt.json", commit=commit, files=files, archive_path=archive_path)
    write_provenance(
        metadata_dir / "source-provenance.txt",
        commit=commit,
        tree_digest=tree_digest,
        archive_sha256=archive_sha256,
        archive_name=archive_path.name,
    )

    return ImportResult(
        source_commit=commit,
        staging_root=staging_root,
        archive_path=archive_path,
        tree_digest=tree_digest,
        archive_sha256=archive_sha256,
        file_count=len(files),
    )


def cmd_import(args: argparse.Namespace) -> int:
    result = run_import(
        source_repo=Path(args.source_repo),
        staging_root=Path(args.staging_root),
        archive_dir=Path(args.archive_dir),
        metadata_dir=Path(args.metadata_dir),
        inventory_path=Path(args.inventory),
    )
    print(f"imported {result.file_count} files from {result.source_commit}")
    print(f"staging_root: {result.staging_root}")
    print(f"archive_path: {result.archive_path}")
    print(f"source_tree_digest: sha256:{result.tree_digest}")
    print(f"source_archive_sha256: sha256:{result.archive_sha256}")
    print("metadata updated: import-receipt.json, source-provenance.txt")
    print("public source tree was not modified; copy from staging_root if needed")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    verify_public_boundary(Path(args.repo_root))
    print("routing-edge import boundary verified")
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="routing-edge closed import boundary")
    sub = parser.add_subparsers(dest="command", required=True)

    import_cmd = sub.add_parser("import", help="import pinned git blobs into empty staging and archive dirs")
    import_cmd.add_argument("--source-repo", required=True)
    import_cmd.add_argument("--staging-root", required=True)
    import_cmd.add_argument("--archive-dir", required=True)
    import_cmd.add_argument("--metadata-dir", required=True)
    import_cmd.add_argument("--inventory", required=True)
    import_cmd.set_defaults(func=cmd_import)

    verify_cmd = sub.add_parser("verify", help="verify committed public import boundary")
    verify_cmd.add_argument("--repo-root", required=True)
    verify_cmd.set_defaults(func=cmd_verify)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
