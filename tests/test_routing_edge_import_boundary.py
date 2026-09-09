#!/usr/bin/env python3
# Boundary tests for routing-edge closed import (INSPR-390 correction).
#
# SPDX-License-Identifier: AGPL-3.0-only
from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
BOUNDARY_PATH = REPO_ROOT / "packages/routing-edge/import/boundary.py"
IMPORT_DIR = REPO_ROOT / "packages/routing-edge/import"


def load_boundary():
    spec = importlib.util.spec_from_file_location("routing_edge_import_boundary", BOUNDARY_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


boundary = load_boundary()


def clone_public_tree(tmp: Path) -> Path:
    import shutil

    workspace = tmp / "repo"
    workspace.mkdir()
    shutil.copytree(REPO_ROOT / "contracts/routing", workspace / "contracts/routing")
    shutil.copytree(
        REPO_ROOT / "packages/routing-edge",
        workspace / "packages/routing-edge",
        ignore=shutil.ignore_patterns("__pycache__", ".tmp"),
    )
    for root, dirs, files in os.walk(workspace):
        os.chmod(root, 0o755)
        for name in files:
            os.chmod(Path(root) / name, 0o644)
    return workspace


def init_git_repo(root: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.email", "fixture@example.invalid"], cwd=root, check=True)
    subprocess.run(["git", "config", "user.name", "Fixture"], cwd=root, check=True)


def commit_all(root: Path, message: str) -> str:
    subprocess.run(["git", "add", "-A"], cwd=root, check=True)
    subprocess.run(["git", "commit", "-q", "-m", message], cwd=root, check=True)
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()


def build_fixture_source_repo(tmp: Path, paths: list[str]) -> tuple[Path, str]:
    repo = tmp / "source"
    repo.mkdir()
    init_git_repo(repo)
    for path in paths:
        dest = repo / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(f"fixture:{path}\n", encoding="utf-8")
    commit = commit_all(repo, "fixture source")
    return repo, commit


class InventoryValidationTests(unittest.TestCase):
    def test_rejects_duplicate_paths(self) -> None:
        inventory = json.loads((IMPORT_DIR / "closed-inventory.json").read_text(encoding="utf-8"))
        broken = dict(inventory)
        broken["paths"] = inventory["paths"] + [inventory["paths"][0]]
        with self.assertRaisesRegex(ValueError, "duplicate"):
            boundary.validate_inventory(broken)

    def test_rejects_traversal(self) -> None:
        inventory = json.loads((IMPORT_DIR / "closed-inventory.json").read_text(encoding="utf-8"))
        broken = dict(inventory)
        broken["paths"] = list(inventory["paths"])
        broken["paths"][0] = "../escape"
        with self.assertRaisesRegex(ValueError, "traversal"):
            boundary.validate_inventory(broken)


class ArchiveBoundaryTests(unittest.TestCase):
    def test_archive_content_mismatch_fail_verification(self) -> None:
        files = [
            boundary.FileRecord(
                "contracts/routing/validate.py",
                "abc",
                boundary._sha256_bytes(b"test"),
                4,
                b"test",
                0o100644,
            ),
        ]
        wrong = [
            boundary.FileRecord(
                "contracts/routing/validate.py",
                "abc",
                boundary._sha256_bytes(b"wrong"),
                5,
                b"wrong",
                0o100644,
            ),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            archive = Path(tmpdir) / "fixture.tar"
            boundary.build_gnu_deterministic_tar(archive, files)
            with self.assertRaisesRegex(ValueError, "content mismatch"):
                boundary.verify_tar_archive(archive, wrong)

    def test_archive_byte_truncation_fail_verification(self) -> None:
        files = [
            boundary.FileRecord(
                "contracts/routing/validate.py",
                "abc",
                boundary._sha256_bytes(b"test"),
                4,
                b"test",
                0o100644,
            ),
        ]
        with tempfile.TemporaryDirectory() as tmpdir:
            archive = Path(tmpdir) / "fixture.tar"
            boundary.build_gnu_deterministic_tar(archive, files)
            boundary.verify_tar_archive(archive, files)
            archive.write_bytes(b"")
            with self.assertRaises((EOFError, ValueError, tarfile.TarError)):
                boundary.verify_tar_archive(archive, files)

    def test_tree_digest_is_not_archive_digest(self) -> None:
        files = [
            boundary.FileRecord(
                "contracts/routing/validate.py",
                "abc",
                boundary._sha256_bytes(b"x"),
                1,
                b"x",
            )
        ]
        tree = boundary.compute_tree_digest(files)
        with tempfile.TemporaryDirectory() as tmpdir:
            archive = Path(tmpdir) / "fixture.tar"
            boundary.build_gnu_deterministic_tar(archive, files)
            archive_sha = boundary._sha256_file(archive)
        self.assertNotEqual(tree, archive_sha)


class StagingBoundaryTests(unittest.TestCase):
    def test_nonempty_staging_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            staging = Path(tmpdir) / "staging"
            staging.mkdir()
            (staging / "already-there").write_text("nope", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "must be empty"):
                boundary.ensure_empty_output_root(staging, label="staging root")

    def test_symlink_staging_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            target = Path(tmpdir) / "target"
            target.mkdir()
            link = Path(tmpdir) / "link"
            link.symlink_to(target)
            with self.assertRaisesRegex(ValueError, "symlink"):
                boundary.ensure_empty_output_root(link, label="staging root")

    def test_symlink_destination_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            staging = (Path(tmpdir) / "staging").resolve()
            elsewhere = (Path(tmpdir) / "elsewhere").resolve()
            staging.mkdir()
            elsewhere.mkdir()
            (staging / "contracts").symlink_to(elsewhere)
            with self.assertRaisesRegex(ValueError, "symlink ancestor"):
                boundary._reject_symlink_ancestor(staging / "contracts/routing", within=staging)


class GitSourceBoundaryTests(unittest.TestCase):
    def test_symlink_blob_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = Path(tmpdir) / "source"
            repo.mkdir()
            init_git_repo(repo)
            target = repo / "target.txt"
            target.write_text("secret\n", encoding="utf-8")
            link = repo / "contracts/routing/validate.py"
            link.parent.mkdir(parents=True)
            link.symlink_to(target)
            commit = commit_all(repo, "symlink fixture")
            inventory = {
                "schema": boundary.INVENTORY_SCHEMA,
                "source_commit": commit,
                "path_count": 1,
                "paths": ["contracts/routing/validate.py"],
            }
            with self.assertRaisesRegex(ValueError, "outside closed inventory|symlink"):
                boundary.git_read_closed_slice(repo, commit, inventory["paths"])

    def test_import_writes_only_to_staging(self) -> None:
        paths = boundary.validate_inventory(
            json.loads((IMPORT_DIR / "closed-inventory.json").read_text(encoding="utf-8"))
        )
        with tempfile.TemporaryDirectory() as tmpdir:
            repo, commit = build_fixture_source_repo(Path(tmpdir), paths)
            inventory_path = Path(tmpdir) / "inventory.json"
            inventory_path.write_text(
                json.dumps(
                    {
                        "schema": boundary.INVENTORY_SCHEMA,
                        "source_commit": commit,
                        "path_count": 48,
                        "paths": paths,
                    }
                ),
                encoding="utf-8",
            )
            staging = Path(tmpdir) / "staging"
            archive_dir = Path(tmpdir) / "archives"
            metadata_dir = Path(tmpdir) / "metadata"
            metadata_dir.mkdir()
            result = boundary.run_import(
                source_repo=repo,
                staging_root=staging,
                archive_dir=archive_dir,
                metadata_dir=metadata_dir,
                inventory_path=inventory_path,
            )
            self.assertEqual(result.file_count, 48)
            self.assertTrue(result.archive_path.is_file())
            boundary.verify_tar_archive(result.archive_path, boundary.git_read_closed_slice(repo, commit, paths))
            public_validate = REPO_ROOT / "contracts/routing/validate.py"
            self.assertTrue(public_validate.is_file())
            self.assertNotEqual(public_validate.read_bytes(), (staging / "contracts/routing/validate.py").read_bytes())


class PublicVerificationTests(unittest.TestCase):
    def test_public_boundary_happy_path(self) -> None:
        boundary.verify_public_boundary(REPO_ROOT)

    def test_tampered_receipt_tree_digest_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace = clone_public_tree(Path(tmpdir))
            receipt = json.loads((workspace / "packages/routing-edge/import/import-receipt.json").read_text())
            receipt["tree_digest"] = "sha256:deadbeef"
            (workspace / "packages/routing-edge/import/import-receipt.json").write_text(
                json.dumps(receipt, indent=2) + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "tree_digest"):
                boundary.verify_public_boundary(workspace)

    def test_bad_adaptation_source_commit_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace = clone_public_tree(Path(tmpdir))
            adaptations = json.loads(
                (workspace / "packages/routing-edge/import/public-adaptations.json").read_text(encoding="utf-8")
            )
            adaptations["source_commit"] = "0" * 40
            (workspace / "packages/routing-edge/import/public-adaptations.json").write_text(
                json.dumps(adaptations, indent=2) + "\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(ValueError, "source_commit"):
                boundary.verify_public_boundary(workspace)

    def test_duplicate_adaptation_path_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace = clone_public_tree(Path(tmpdir))
            path = workspace / "packages/routing-edge/import/public-adaptations.json"
            adaptations = json.loads(path.read_text(encoding="utf-8"))
            adaptations["adapted_paths"].append(dict(adaptations["adapted_paths"][0]))
            path.write_text(json.dumps(adaptations, indent=2) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate"):
                boundary.verify_public_boundary(workspace)

    def test_vague_adaptation_reason_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace = clone_public_tree(Path(tmpdir))
            path = workspace / "packages/routing-edge/import/public-adaptations.json"
            adaptations = json.loads(path.read_text(encoding="utf-8"))
            adaptations["adapted_paths"][0]["reason"] = "version bump"
            path.write_text(json.dumps(adaptations, indent=2) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "too vague"):
                boundary.verify_public_boundary(workspace)

    def test_tampered_provenance_archive_sha256_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace = clone_public_tree(Path(tmpdir))
            provenance_path = workspace / "packages/routing-edge/import/source-provenance.txt"
            provenance = provenance_path.read_text(encoding="utf-8").replace(
                "source_archive_sha256: sha256:",
                "source_archive_sha256: sha256:deadbeef",
                1,
            )
            provenance_path.write_text(provenance, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "archive sha256"):
                boundary.verify_public_boundary(workspace)

    def test_unexpected_metadata_file_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            workspace = clone_public_tree(Path(tmpdir))
            extra = workspace / "packages/routing-edge/import/extra.txt"
            extra.write_text("unexpected\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "metadata inventory mismatch"):
                boundary.verify_public_boundary(workspace)


if __name__ == "__main__":
    unittest.main(verbosity=2)
