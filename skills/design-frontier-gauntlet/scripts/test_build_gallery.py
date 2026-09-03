#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Focused tests for build_gallery.py using disposable run roots."""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

SCRIPT = Path(__file__).with_name("build_gallery.py")
IDS = (
    "codex-imagegen",
    "claude-fable",
    "higgsfield-structure",
    "higgsfield-spatial",
    "higgsfield-precision",
)


def manifest() -> dict:
    concepts = []
    for index, concept_id in enumerate(IDS, 1):
        provider = "Higgsfield"
        model = f"Model {index}"
        if concept_id == "codex-imagegen":
            provider = "OpenAI"
            model = "built-in ImageGen"
        elif concept_id == "claude-fable":
            provider = "Anthropic"
            model = "Claude Fable 5.1"
        concepts.append(
            {
                "id": concept_id,
                "label": f"Lens {index}",
                "provider": provider,
                "model": model,
                "status": "ready",
                "entry": f"concepts/{concept_id}/index.html",
                "thesis": f"Distinct thesis {index}",
                "note": "Local simulation with no production calls.",
                "worker": {
                    "name": f"worker-{index}",
                    "uuid": f"123e4567-e89b-42d3-a456-4266141740{index:02d}",
                },
            }
        )
        if concept_id.startswith("higgsfield-"):
            concepts[-1]["model_evidence"] = {
                "cli_version": "1.1.24",
                "discovery_date": datetime.now(timezone.utc).date().isoformat(),
                "display_name": f"Model {index}",
                "job_type": f"model_{index}",
                "parameters": ["prompt", "resolution"],
                "official_sources": ["https://higgsfield.ai/ai-image"],
            }
    return {
        "schema_version": 1,
        "ticket": "PAI-999",
        "title": "A safer agent workspace",
        "summary": "Five independent ways to make the same work visible.",
        "concepts": concepts,
    }


def prepare(root: Path, data: dict) -> None:
    for item in data["concepts"]:
        if item["status"] == "ready":
            entry = root / item["entry"]
            entry.parent.mkdir(parents=True, exist_ok=True)
            entry.write_text(f"<!doctype html><title>{item['label']}</title>", encoding="utf-8")
    (root / "manifest.json").write_text(json.dumps(data), encoding="utf-8")


def run(root: Path, *, expect_ok: bool, output: Optional[Path] = None) -> subprocess.CompletedProcess[str]:
    command = ["python3", str(SCRIPT), "--root", str(root)]
    if output is not None:
        command.extend(["--output", str(output)])
    result = subprocess.run(
        command,
        text=True,
        capture_output=True,
        check=False,
    )
    if (result.returncode == 0) != expect_ok:
        raise AssertionError(f"unexpected exit {result.returncode}\nstdout={result.stdout}\nstderr={result.stderr}")
    return result


def rejected(mutator, expected: str) -> None:
    with tempfile.TemporaryDirectory(prefix="design-frontier-invalid-") as raw:
        root = Path(raw)
        data = manifest()
        mutator(data, root)
        prepare(root, data)
        result = run(root, expect_ok=False)
        if expected not in result.stderr:
            raise AssertionError(f"missing error {expected!r}: {result.stderr}")


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="design-frontier-valid-") as raw:
        root = Path(raw)
        data = manifest()
        data["title"] = '</style><img src=x onerror="alert(1)">'
        data["concepts"][3]["entry"] = "concepts/higgsfield-spatial/Signal #50% ready.html"
        data["concepts"][-1]["status"] = "unavailable"
        data["concepts"][-1].pop("entry")
        data["concepts"][-1]["reason"] = "The selected model is absent from the live catalog."
        prepare(root, data)
        first = run(root, expect_ok=True)
        built = root / "gallery" / "index.html"
        before = built.read_bytes()
        second = run(root, expect_ok=True)
        after = built.read_bytes()
        assert before == after, "gallery output is not deterministic"
        page = after.decode("utf-8")
        assert "4 ready, 1 unavailable" in first.stdout
        assert "4 ready, 1 unavailable" in second.stdout
        assert "No substitute was used." in page
        assert "../concepts/codex-imagegen/index.html" in page
        assert "../concepts/higgsfield-spatial/Signal%20%2350%25%20ready.html" in page
        assert '</style><img src=x onerror="alert(1)">' not in page
        assert "&lt;/style&gt;&lt;img src=x onerror=&quot;alert(1)&quot;&gt;" in page
        assert "123e4567-e89b-42d3-a456-426614174001" in page
        assert "Parameters: prompt, resolution" in page
        assert "Official sources: https://higgsfield.ai/ai-image" in page
        assert page.count('sandbox="allow-scripts"') == 4
        assert page.count('referrerpolicy="no-referrer"') == 4
        assert "allow-same-origin" not in page
        assert "allow-top-navigation" not in page

    with tempfile.TemporaryDirectory(prefix="design-frontier-preflight-") as raw:
        root = Path(raw)
        data = manifest()
        for item in data["concepts"]:
            item["status"] = "unavailable"
            item.pop("entry")
            item.pop("worker")
            item.pop("model_evidence", None)
            item["not_dispatched"] = True
            item["reason"] = "The provider was unavailable during preflight."
        prepare(root, data)
        result = run(root, expect_ok=True)
        page = (root / "gallery" / "index.html").read_text(encoding="utf-8")
        assert "0 ready, 5 unavailable" in result.stdout
        assert page.count("Preflight unavailable") == 5
        assert page.count("WORKER STATE") == 5

    with tempfile.TemporaryDirectory(prefix="design-frontier-uuid7-") as raw:
        root = Path(raw)
        data = manifest()
        data["concepts"][0]["worker"]["uuid"] = "01a066ae-e20a-7b00-9a3a-c26d49433278"
        prepare(root, data)
        run(root, expect_ok=True)

    rejected(lambda data, root: data["concepts"].pop(), "exactly five")
    rejected(
        lambda data, root: data["concepts"][1]["worker"].update(
            uuid=data["concepts"][0]["worker"]["uuid"]
        ),
        "distinct worker UUID",
    )
    rejected(
        lambda data, root: data["concepts"][0].update(entry="../outside.html"),
        "relative HTML path",
    )
    rejected(
        lambda data, root: data["concepts"][1].update(entry=data["concepts"][0]["entry"]),
        "distinct entry paths",
    )
    rejected(
        lambda data, root: data["concepts"][1].update(entry="concepts/codex-imagegen/other.html"),
        "must live below concepts/claude-fable/",
    )
    rejected(
        lambda data, root: data["concepts"][0].update(status="unavailable", entry=None),
        "reason must be a non-empty string",
    )
    rejected(
        lambda data, root: data["concepts"][0].update(worker=None),
        "unless an unavailable lens sets not_dispatched=true",
    )
    rejected(
        lambda data, root: data["concepts"][0].update(not_dispatched=True),
        "has a worker and must not be marked not_dispatched",
    )
    rejected(
        lambda data, root: data["concepts"][0].update(id="unknown-lens"),
        "unknown concept id",
    )
    rejected(
        lambda data, root: data["concepts"][0].update(model="GPT Image API"),
        "must use OpenAI built-in ImageGen",
    )
    rejected(
        lambda data, root: data["concepts"][1].update(model="Claude Opus 5"),
        "must use exact Claude Fable 5.1",
    )
    rejected(
        lambda data, root: data["concepts"][1].update(model="Fake Fable 5.1 via substitute"),
        "must use exact Claude Fable 5.1",
    )
    rejected(
        lambda data, root: data["concepts"][2].update(provider="OpenAI"),
        "must use Higgsfield and match model_evidence.display_name exactly",
    )
    rejected(
        lambda data, root: data["concepts"][2].update(model="DALL-E 3"),
        "must use Higgsfield and match model_evidence.display_name exactly",
    )
    rejected(
        lambda data, root: data["concepts"][3]["model_evidence"].update(
            job_type=data["concepts"][2]["model_evidence"]["job_type"]
        ),
        "distinct job_type and display_name",
    )

    def duplicate_higgsfield_display_name(data: dict, _root: Path) -> None:
        duplicate = data["concepts"][2]["model_evidence"]["display_name"]
        data["concepts"][3]["model_evidence"]["display_name"] = duplicate
        data["concepts"][3]["model"] = duplicate

    rejected(
        duplicate_higgsfield_display_name,
        "distinct job_type and display_name",
    )
    rejected(
        lambda data, root: data["concepts"][2]["model_evidence"].update(discovery_date="20260903"),
        "must be YYYY-MM-DD",
    )
    rejected(
        lambda data, root: data["concepts"][2]["model_evidence"].update(
            discovery_date=(datetime.now(timezone.utc).date() + timedelta(days=1)).isoformat()
        ),
        "must not be in the future",
    )
    rejected(
        lambda data, root: data["concepts"][2]["model_evidence"].update(
            discovery_date=(datetime.now(timezone.utc).date() - timedelta(days=8)).isoformat()
        ),
        "is stale",
    )
    rejected(
        lambda data, root: data["concepts"][2]["model_evidence"].update(
            official_sources=["https://higgsfield.ai:8443/ai-image"]
        ),
        "credential-free higgsfield.ai HTTPS URLs",
    )
    rejected(
        lambda data, root: data["concepts"][2]["model_evidence"].update(
            official_sources=["https://higgsfield.ai:not-a-port/ai-image"]
        ),
        "must use a valid HTTPS port",
    )
    rejected(
        lambda data, root: data["concepts"][2]["model_evidence"].update(
            official_sources=["https://example.com/ai-image"]
        ),
        "credential-free higgsfield.ai HTTPS URLs",
    )
    rejected(
        lambda data, root: data["concepts"][0].update(model_evidence={"job_type": "not_allowed"}),
        "must not carry model_evidence",
    )

    def remove_model_evidence(data: dict, _root: Path) -> None:
        data["concepts"][2].pop("model_evidence")

    rejected(remove_model_evidence, "model_evidence must be an object")
    with tempfile.TemporaryDirectory(prefix="design-frontier-root-") as raw_root:
        with tempfile.TemporaryDirectory(prefix="design-frontier-outside-") as raw_outside:
            root = Path(raw_root)
            prepare(root, manifest())
            (root / "gallery").symlink_to(Path(raw_outside), target_is_directory=True)
            result = run(root, expect_ok=False)
            assert "output must remain below the run root" in result.stderr

    with tempfile.TemporaryDirectory(prefix="design-frontier-entry-link-") as raw_root:
        with tempfile.TemporaryDirectory(prefix="design-frontier-entry-outside-") as raw_outside:
            root = Path(raw_root)
            data = manifest()
            prepare(root, data)
            entry = root / data["concepts"][0]["entry"]
            entry.unlink()
            entry.symlink_to(Path(raw_outside) / "outside.html")
            result = run(root, expect_ok=False)
            assert "entry path must not contain symbolic links" in result.stderr

    with tempfile.TemporaryDirectory(prefix="design-frontier-lens-link-") as raw_root:
        with tempfile.TemporaryDirectory(prefix="design-frontier-lens-outside-") as raw_outside:
            root = Path(raw_root)
            data = manifest()
            prepare(root, data)
            lens = root / "concepts" / "codex-imagegen"
            entry = lens / "index.html"
            entry.unlink()
            lens.rmdir()
            outside = Path(raw_outside)
            (outside / "index.html").write_text("<!doctype html><title>outside</title>", encoding="utf-8")
            lens.symlink_to(outside, target_is_directory=True)
            result = run(root, expect_ok=False)
            assert "entry path must not contain symbolic links" in result.stderr

    with tempfile.TemporaryDirectory(prefix="design-frontier-sibling-link-") as raw:
        root = Path(raw)
        data = manifest()
        prepare(root, data)
        lens = root / "concepts" / "claude-fable"
        (lens / "index.html").unlink()
        lens.rmdir()
        lens.symlink_to(root / "concepts" / "codex-imagegen", target_is_directory=True)
        result = run(root, expect_ok=False)
        assert "entry path must not contain symbolic links" in result.stderr

    with tempfile.TemporaryDirectory(prefix="design-frontier-nested-link-") as raw:
        root = Path(raw)
        data = manifest()
        data["concepts"][0]["entry"] = "concepts/codex-imagegen/nested/index.html"
        prepare(root, data)
        nested = root / "concepts" / "codex-imagegen" / "nested"
        (nested / "index.html").unlink()
        nested.rmdir()
        nested.symlink_to(root / "concepts" / "claude-fable", target_is_directory=True)
        result = run(root, expect_ok=False)
        assert "entry path must not contain symbolic links" in result.stderr

    with tempfile.TemporaryDirectory(prefix="design-frontier-hardlink-alias-") as raw:
        root = Path(raw)
        data = manifest()
        prepare(root, data)
        source = root / data["concepts"][0]["entry"]
        alias = root / data["concepts"][1]["entry"]
        alias.unlink()
        os.link(source, alias)
        result = run(root, expect_ok=False)
        assert "distinct files, not filesystem aliases" in result.stderr

    with tempfile.TemporaryDirectory(prefix="design-frontier-output-clobber-") as raw:
        root = Path(raw)
        data = manifest()
        prepare(root, data)
        output = root / data["concepts"][0]["entry"]
        result = run(root, expect_ok=False, output=output)
        assert "output must not be inside the concepts directory" in result.stderr

    with tempfile.TemporaryDirectory(prefix="design-frontier-manifest-clobber-") as raw:
        root = Path(raw)
        data = manifest()
        prepare(root, data)
        result = run(root, expect_ok=False, output=root / "manifest.json")
        assert "output must be an HTML file" in result.stderr
        assert json.loads((root / "manifest.json").read_text(encoding="utf-8")) == data

    with tempfile.TemporaryDirectory(prefix="design-frontier-existing-html-") as raw:
        root = Path(raw)
        data = manifest()
        prepare(root, data)
        output = root / "notes.html"
        output.write_text("operator notes", encoding="utf-8")
        result = run(root, expect_ok=False, output=output)
        assert "refusing to replace a file not generated" in result.stderr
        assert output.read_text(encoding="utf-8") == "operator notes"

    with tempfile.TemporaryDirectory(prefix="design-frontier-root-file-") as raw:
        root_file = Path(raw) / "not-a-directory"
        root_file.write_text("data", encoding="utf-8")
        result = run(root_file, expect_ok=False)
        assert result.stderr.startswith("error:")
        assert "Traceback" not in result.stderr

    with tempfile.TemporaryDirectory(prefix="design-frontier-gallery-file-") as raw:
        root = Path(raw)
        prepare(root, manifest())
        (root / "gallery").write_text("not a directory", encoding="utf-8")
        result = run(root, expect_ok=False)
        assert result.stderr.startswith("error:")
        assert "Traceback" not in result.stderr

    print("ok: deterministic gallery, UUIDv7/preflight states, and fail-closed contract cases")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
