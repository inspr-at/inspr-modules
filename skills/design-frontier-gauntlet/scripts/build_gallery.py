#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Build a deterministic, local-only comparison gallery for five concepts."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlsplit

REQUIRED_IDS = (
    "codex-imagegen",
    "claude-fable",
    "higgsfield-structure",
    "higgsfield-spatial",
    "higgsfield-precision",
)
UUID_RE = re.compile(
    r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
    re.IGNORECASE,
)
TICKET_RE = re.compile(r"^[A-Z][A-Z0-9]+-[1-9][0-9]*$")
MAX_MANIFEST_BYTES = 512 * 1024
MAX_DISCOVERY_AGE_DAYS = 7
GALLERY_MARKER = '<meta name="generator" content="design-frontier-gauntlet-v1">'
FABLE_5_1_MODEL_NAMES = frozenset(("claude fable 5.1", "claude-fable-5-1"))


class ContractError(ValueError):
    """Manifest or filesystem state violates the gallery contract."""


def text_field(value: Any, field: str, *, max_length: int = 600) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ContractError(f"{field} must be a non-empty string")
    normalized = value.strip()
    if len(normalized) > max_length:
        raise ContractError(f"{field} exceeds {max_length} characters")
    return normalized


def load_manifest(root: Path) -> dict[str, Any]:
    source = root / "manifest.json"
    try:
        size = source.stat().st_size
    except OSError as exc:
        if isinstance(exc, FileNotFoundError):
            raise ContractError("manifest.json is missing") from exc
        raise ContractError(f"manifest.json cannot be read: {exc.strerror or type(exc).__name__}") from exc
    if size > MAX_MANIFEST_BYTES:
        raise ContractError("manifest.json exceeds 512 KiB")
    try:
        data = json.loads(source.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ContractError(f"manifest.json cannot be read: {exc.strerror or type(exc).__name__}") from exc
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ContractError(f"manifest.json is not valid UTF-8 JSON: {exc}") from exc
    if not isinstance(data, dict):
        raise ContractError("manifest root must be an object")
    return data


def validate_model_evidence(raw: Any, concept_id: str) -> dict[str, Any]:
    if not isinstance(raw, dict):
        raise ContractError(f"{concept_id}.model_evidence must be an object")
    cli_version = text_field(raw.get("cli_version"), f"{concept_id}.model_evidence.cli_version", max_length=40)
    discovery_date = text_field(
        raw.get("discovery_date"), f"{concept_id}.model_evidence.discovery_date", max_length=10
    )
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", discovery_date):
        raise ContractError(f"{concept_id}.model_evidence.discovery_date must be YYYY-MM-DD")
    try:
        discovered = date.fromisoformat(discovery_date)
    except ValueError as exc:
        raise ContractError(f"{concept_id}.model_evidence.discovery_date must be YYYY-MM-DD") from exc
    age_days = (datetime.now(timezone.utc).date() - discovered).days
    if age_days < 0:
        raise ContractError(f"{concept_id}.model_evidence.discovery_date must not be in the future")
    if age_days > MAX_DISCOVERY_AGE_DAYS:
        raise ContractError(
            f"{concept_id}.model_evidence is stale; repeat live discovery within {MAX_DISCOVERY_AGE_DAYS} days"
        )
    display_name = text_field(
        raw.get("display_name"), f"{concept_id}.model_evidence.display_name", max_length=120
    )
    job_type = text_field(raw.get("job_type"), f"{concept_id}.model_evidence.job_type", max_length=80)
    if not re.fullmatch(r"[a-z0-9][a-z0-9_]*", job_type):
        raise ContractError(f"{concept_id}.model_evidence.job_type must be a live job_type identifier")

    parameters = raw.get("parameters")
    if not isinstance(parameters, list) or not parameters or len(parameters) > 30:
        raise ContractError(f"{concept_id}.model_evidence.parameters must contain 1 to 30 names")
    normalized_parameters = [
        text_field(value, f"{concept_id}.model_evidence.parameters", max_length=80) for value in parameters
    ]
    if len(set(normalized_parameters)) != len(normalized_parameters):
        raise ContractError(f"{concept_id}.model_evidence.parameters must be unique")

    official_sources = raw.get("official_sources")
    if not isinstance(official_sources, list) or not 1 <= len(official_sources) <= 4:
        raise ContractError(f"{concept_id}.model_evidence.official_sources must contain 1 to 4 URLs")
    normalized_sources = []
    for source in official_sources:
        source = text_field(source, f"{concept_id}.model_evidence.official_sources", max_length=240)
        parsed = urlsplit(source)
        try:
            port = parsed.port
        except ValueError as exc:
            raise ContractError(
                f"{concept_id}.model_evidence.official_sources must use a valid HTTPS port"
            ) from exc
        if (
            parsed.scheme != "https"
            or parsed.hostname not in ("higgsfield.ai", "www.higgsfield.ai")
            or parsed.username is not None
            or parsed.password is not None
            or port not in (None, 443)
            or parsed.query
            or parsed.fragment
        ):
            raise ContractError(
                f"{concept_id}.model_evidence.official_sources must be credential-free higgsfield.ai HTTPS URLs"
            )
        normalized_sources.append(source)

    return {
        "cli_version": cli_version,
        "discovery_date": discovery_date,
        "display_name": display_name,
        "job_type": job_type,
        "parameters": normalized_parameters,
        "official_sources": normalized_sources,
    }


def validate(root: Path, data: dict[str, Any]) -> list[dict[str, Any]]:
    if data.get("schema_version") != 1:
        raise ContractError("schema_version must equal 1")
    ticket = text_field(data.get("ticket"), "ticket", max_length=40)
    if not TICKET_RE.fullmatch(ticket):
        raise ContractError("ticket must look like PRODUCT-123")
    text_field(data.get("title"), "title", max_length=120)
    text_field(data.get("summary"), "summary")

    concepts = data.get("concepts")
    if not isinstance(concepts, list) or len(concepts) != len(REQUIRED_IDS):
        raise ContractError("concepts must contain exactly five entries")

    normalized: list[dict[str, Any]] = []
    ids: set[str] = set()
    workers: set[str] = set()
    entries: set[str] = set()
    resolved_entries: set[Path] = set()
    entry_file_identities: set[tuple[int, int]] = set()
    higgsfield_job_types: set[str] = set()
    higgsfield_display_names: set[str] = set()
    root_real = root.resolve()
    for position, raw in enumerate(concepts):
        if not isinstance(raw, dict):
            raise ContractError(f"concepts[{position}] must be an object")
        concept_id = text_field(raw.get("id"), f"concepts[{position}].id", max_length=40)
        if concept_id not in REQUIRED_IDS:
            raise ContractError(f"unknown concept id: {concept_id}")
        if concept_id in ids:
            raise ContractError(f"duplicate concept id: {concept_id}")
        ids.add(concept_id)

        label = text_field(raw.get("label"), f"{concept_id}.label", max_length=80)
        provider = text_field(raw.get("provider"), f"{concept_id}.provider", max_length=80)
        model = text_field(raw.get("model"), f"{concept_id}.model", max_length=120)

        status = raw.get("status")
        if status not in ("ready", "unavailable"):
            raise ContractError(f"{concept_id}.status must be ready or unavailable")
        worker = raw.get("worker")
        not_dispatched = raw.get("not_dispatched")
        if isinstance(worker, dict):
            if not_dispatched not in (None, False):
                raise ContractError(f"{concept_id} has a worker and must not be marked not_dispatched")
            worker_name = text_field(worker.get("name"), f"{concept_id}.worker.name", max_length=80)
            worker_uuid = text_field(worker.get("uuid"), f"{concept_id}.worker.uuid", max_length=36)
            if not UUID_RE.fullmatch(worker_uuid):
                raise ContractError(f"{concept_id}.worker.uuid is not a canonical RFC 9562 UUID")
            lowered_uuid = worker_uuid.lower()
            if lowered_uuid in workers:
                raise ContractError("each dispatched concept must have a distinct worker UUID")
            workers.add(lowered_uuid)
            worker_label = "Builder"
        elif status == "unavailable" and not_dispatched is True:
            worker_name = "Not dispatched"
            worker_uuid = "Preflight unavailable"
            worker_label = "Worker state"
        else:
            raise ContractError(
                f"{concept_id}.worker must be an object unless an unavailable lens sets not_dispatched=true"
            )

        if concept_id == "codex-imagegen" and isinstance(worker, dict):
            if provider.casefold() != "openai" or model.casefold() != "built-in imagegen":
                raise ContractError("codex-imagegen must use OpenAI built-in ImageGen")
        if concept_id == "claude-fable" and isinstance(worker, dict):
            if provider.casefold() != "anthropic" or model.casefold() not in FABLE_5_1_MODEL_NAMES:
                raise ContractError("claude-fable must use exact Claude Fable 5.1, not a substitute model")

        model_evidence = None
        if concept_id.startswith("higgsfield-") and isinstance(worker, dict):
            model_evidence = validate_model_evidence(raw.get("model_evidence"), concept_id)
            if provider != "Higgsfield" or model != model_evidence["display_name"]:
                raise ContractError(
                    f"{concept_id} must use Higgsfield and match model_evidence.display_name exactly"
                )
            job_type = model_evidence["job_type"]
            display_name = model_evidence["display_name"].casefold()
            if job_type in higgsfield_job_types or display_name in higgsfield_display_names:
                raise ContractError(
                    "dispatched Higgsfield lenses must use distinct job_type and display_name values"
                )
            higgsfield_job_types.add(job_type)
            higgsfield_display_names.add(display_name)
        elif raw.get("model_evidence") not in (None, {}):
            raise ContractError(f"{concept_id} must not carry model_evidence")

        entry = ""
        reason = ""
        if status == "ready":
            entry_raw = text_field(raw.get("entry"), f"{concept_id}.entry", max_length=240)
            entry_path = Path(entry_raw)
            if entry_path.is_absolute() or ".." in entry_path.parts or entry_path.suffix.lower() != ".html":
                raise ContractError(f"{concept_id}.entry must be a relative HTML path below the run root")
            entry = entry_path.as_posix()
            if entry in entries:
                raise ContractError("ready concepts must use distinct entry paths")
            entries.add(entry)
            if len(entry_path.parts) < 3 or entry_path.parts[:2] != ("concepts", concept_id):
                raise ContractError(f"{concept_id}.entry must live below concepts/{concept_id}/")
            declared = root_real
            for part in entry_path.parts:
                declared /= part
                if declared.is_symlink():
                    raise ContractError(f"{concept_id}.entry path must not contain symbolic links")
            expected_directory = root_real / "concepts" / concept_id
            resolved = (root_real / entry_path).resolve()
            if (
                not resolved.is_relative_to(root_real)
                or not resolved.is_relative_to(expected_directory)
                or not resolved.is_file()
            ):
                raise ContractError(f"{concept_id}.entry does not resolve to a file below its lens directory")
            if resolved in resolved_entries:
                raise ContractError("ready concepts must resolve to distinct entry files")
            resolved_entries.add(resolved)
            try:
                file_stat = resolved.stat()
            except OSError as exc:
                raise ContractError(
                    f"{concept_id}.entry cannot be inspected: {exc.strerror or type(exc).__name__}"
                ) from exc
            file_identity = (file_stat.st_dev, file_stat.st_ino)
            if file_identity in entry_file_identities:
                raise ContractError("ready concepts must be distinct files, not filesystem aliases")
            entry_file_identities.add(file_identity)
            if raw.get("reason") not in (None, ""):
                raise ContractError(f"{concept_id} is ready and must not carry an unavailable reason")
        else:
            if raw.get("entry") not in (None, ""):
                raise ContractError(f"{concept_id} is unavailable and must not carry an entry")
            reason = text_field(raw.get("reason"), f"{concept_id}.reason")

        normalized.append(
            {
                "id": concept_id,
                "label": label,
                "provider": provider,
                "model": model,
                "status": status,
                "entry": entry,
                "reason": reason,
                "thesis": text_field(raw.get("thesis"), f"{concept_id}.thesis"),
                "note": text_field(raw.get("note"), f"{concept_id}.note"),
                "worker_name": worker_name,
                "worker_uuid": worker_uuid,
                "worker_label": worker_label,
                "model_evidence": model_evidence,
            }
        )

    if ids != set(REQUIRED_IDS):
        missing = sorted(set(REQUIRED_IDS) - ids)
        raise ContractError(f"required concept ids missing: {', '.join(missing)}")
    order = {concept_id: index for index, concept_id in enumerate(REQUIRED_IDS)}
    return sorted(normalized, key=lambda item: order[item["id"]])


def escape(value: Any) -> str:
    return html.escape(str(value), quote=True)


def render(root: Path, output: Path, data: dict[str, Any], concepts: list[dict[str, Any]]) -> str:
    cards = []
    panels = []
    for index, concept in enumerate(concepts):
        ready = concept["status"] == "ready"
        badge = "READY" if ready else "UNAVAILABLE"
        cards.append(
            f'''<button class="lens-card{' is-active' if index == 0 else ''}" type="button" data-lens="{escape(concept['id'])}" aria-pressed="{'true' if index == 0 else 'false'}">
  <span class="number">0{index + 1}</span><span><small>{escape(concept['provider'])} · {escape(concept['model'])}</small><strong>{escape(concept['label'])}</strong><em>{escape(concept['thesis'])}</em></span><b class="status {'ready' if ready else 'unavailable'}">{badge}</b>
</button>'''
        )
        if ready:
            absolute_entry = (root / concept["entry"]).resolve()
            source = Path(os.path.relpath(absolute_entry, output.parent)).as_posix()
            body = f'<iframe src="{escape(quote(source, safe="/"))}" title="{escape(concept["label"])} interactive concept" loading="lazy" sandbox="allow-scripts" referrerpolicy="no-referrer"></iframe>'
        else:
            body = f'''<div class="unavailable-panel"><span>◇</span><h3>Lens unavailable</h3><p>{escape(concept['reason'])}</p><small>No substitute was used.</small></div>'''
        evidence = concept["model_evidence"]
        evidence_html = ""
        if evidence is not None:
            parameters = ", ".join(evidence["parameters"])
            sources = ", ".join(evidence["official_sources"])
            evidence_html = (
                f'<small class="evidence">{escape(evidence["display_name"])} · '
                f'{escape(evidence["job_type"])} · CLI {escape(evidence["cli_version"])} · '
                f'{escape(evidence["discovery_date"])}<br>Parameters: {escape(parameters)}<br>'
                f'Official sources: {escape(sources)}</small>'
            )
        panels.append(
            f'''<article class="lens-panel{' is-active' if index == 0 else ''}" data-panel="{escape(concept['id'])}">
  <header><div><small>{escape(concept['provider'])} · {escape(concept['model'])}</small><h2>{escape(concept['label'])}</h2><p>{escape(concept['thesis'])}</p>{evidence_html}</div><div class="worker"><span>{escape(concept['worker_label']).upper()}</span><strong>{escape(concept['worker_name'])}</strong><code>{escape(concept['worker_uuid'])}</code></div></header>
  <div class="frame">{body}</div><footer>{escape(concept['note'])}</footer>
</article>'''
        )

    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8">{GALLERY_MARKER}<meta name="viewport" content="width=device-width,initial-scale=1"><title>{escape(data['title'])} · Design frontier</title>
<style>
:root{{--ink:#13241f;--paper:#f1f0e8;--panel:#fbfbf6;--line:#cad6ce;--green:#174b3d;--mint:#88e6c1;--coral:#e88f6c;--muted:#60716a}}*{{box-sizing:border-box}}body{{margin:0;background:var(--paper);color:var(--ink);font-family:Inter,ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}}button{{font:inherit;color:inherit}}button:focus-visible{{outline:3px solid #55b892;outline-offset:3px}}.shell{{min-height:100vh;display:grid;grid-template-columns:330px 1fr}}aside{{padding:28px 20px;border-right:1px solid var(--line);background:rgba(251,251,246,.7)}}.brand{{display:flex;align-items:center;gap:9px;font-weight:800}}.brand i{{width:20px;height:20px;border-radius:50%;background:radial-gradient(circle at 35% 30%,#fff,var(--mint) 24%,var(--green) 68%);box-shadow:0 7px 16px #174b3d33}}.kicker{{display:block;margin-top:48px;font-size:10px;letter-spacing:.16em;color:var(--muted)}}h1{{margin:10px 0 12px;font-size:32px;letter-spacing:-.05em;line-height:1}}.summary{{font:16px/1.4 Georgia,serif;color:var(--muted)}}.switches{{display:flex;gap:5px;margin:22px 0 14px;padding:4px;border:1px solid var(--line);border-radius:11px}}.switches button{{flex:1;padding:8px;border:0;border-radius:8px;background:transparent;font-size:11px;font-weight:750}}.switches button[aria-pressed=true]{{background:var(--green);color:#fff}}.lens-list{{display:grid;gap:7px}}.lens-card{{display:grid;grid-template-columns:28px 1fr auto;width:100%;gap:8px;align-items:start;padding:11px;border:1px solid transparent;border-radius:13px;background:transparent;text-align:left;cursor:pointer}}.lens-card:hover,.lens-card.is-active{{border-color:var(--line);background:var(--panel)}}.lens-card .number{{font:18px Georgia,serif;color:var(--muted)}}.lens-card span:nth-child(2){{display:grid;gap:3px}}.lens-card small{{font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}}.lens-card strong{{font-size:12px}}.lens-card em{{font:11px/1.3 Georgia,serif;color:var(--muted)}}.status{{padding:4px 5px;border-radius:999px;font-size:10px;letter-spacing:.08em}}.status.ready{{background:#d9f5e9;color:#195440}}.status.unavailable{{background:#ffe2d6;color:#8a4028}}.footnote{{margin-top:20px;padding-top:15px;border-top:1px solid var(--line);font-size:10px;line-height:1.5;color:var(--muted)}}main{{min-width:0;padding:20px}}.lens-panel{{display:none}}.lens-panel.is-active{{display:block}}.lens-panel>header{{display:flex;justify-content:space-between;gap:20px;align-items:end;padding:12px 6px 18px}}.lens-panel header small{{font-size:10px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted)}}.lens-panel .evidence{{display:block;margin-top:7px;letter-spacing:.03em;text-transform:none}}h2{{margin:6px 0 3px;font-size:30px;letter-spacing:-.04em}}.lens-panel header p{{margin:0;font:15px Georgia,serif;color:var(--muted)}}.worker{{display:grid;text-align:right;gap:2px}}.worker span{{font-size:10px;color:var(--muted)}}.worker strong{{font-size:10px}}.worker code{{font-size:10px;color:var(--muted)}}.frame{{height:calc(100vh - 145px);min-height:540px;overflow:hidden;border:1px solid var(--line);border-radius:20px;background:var(--panel);box-shadow:0 24px 70px #173e3320}}iframe{{width:100%;height:100%;border:0;background:white}}.unavailable-panel{{height:100%;display:grid;place-content:center;text-align:center;padding:30px}}.unavailable-panel span{{font-size:48px;color:var(--coral)}}.unavailable-panel h3{{margin:15px 0 4px}}.unavailable-panel p{{max-width:430px;color:var(--muted)}}.unavailable-panel small{{color:var(--muted)}}.lens-panel>footer{{padding:10px 6px;color:var(--muted);font-size:10px}}body.matrix main{{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}}body.matrix .lens-panel{{display:block}}body.matrix .lens-panel>header{{align-items:start}}body.matrix .frame{{height:440px;min-height:0}}body.matrix .lens-panel>footer{{display:none}}body.matrix .lens-panel header p{{display:none}}@media(max-width:850px){{.shell{{grid-template-columns:1fr}}aside{{border-right:0;border-bottom:1px solid var(--line)}}.kicker{{margin-top:24px}}.lens-list{{grid-template-columns:repeat(2,1fr)}}main{{padding:12px}}.lens-panel>header{{align-items:start;flex-direction:column}}.worker{{text-align:left}}.frame{{height:70vh;min-height:440px}}body.matrix main{{grid-template-columns:1fr}}}}@media(max-width:520px){{.lens-list{{grid-template-columns:1fr}}.lens-card em{{display:none}}.frame{{border-radius:12px}}}}@media(prefers-reduced-motion:reduce){{*{{scroll-behavior:auto!important;transition:none!important}}}}
</style></head><body><div class="shell"><aside><div class="brand"><i></i>Design frontier</div><span class="kicker">{escape(data['ticket'])} · FIVE BLIND LENSES</span><h1>{escape(data['title'])}</h1><p class="summary">{escape(data['summary'])}</p><div class="switches"><button type="button" data-mode="solo" aria-pressed="true">Solo</button><button type="button" data-mode="matrix" aria-pressed="false">Matrix</button></div><nav class="lens-list" aria-label="Concept lenses">{''.join(cards)}</nav><p class="footnote">Local comparison only. Concept actions may be simulated; no production mutation is implied. Choose a direction—this gallery does not score taste.</p></aside><main>{''.join(panels)}</main></div>
<script>(()=>{{const cards=[...document.querySelectorAll('[data-lens]')],panels=[...document.querySelectorAll('[data-panel]')],modes=[...document.querySelectorAll('[data-mode]')];let selected=cards[0].dataset.lens;function paint(){{const matrix=document.body.classList.contains('matrix');cards.forEach(x=>{{const on=!matrix&&x.dataset.lens===selected;x.classList.toggle('is-active',on);x.setAttribute('aria-pressed',String(on))}});panels.forEach(x=>x.classList.toggle('is-active',matrix||x.dataset.panel===selected));modes.forEach(x=>x.setAttribute('aria-pressed',String((x.dataset.mode==='matrix')===matrix)))}}function select(id){{selected=id;document.body.classList.remove('matrix');paint()}}cards.forEach(x=>x.addEventListener('click',()=>select(x.dataset.lens)));modes.forEach(x=>x.addEventListener('click',()=>{{document.body.classList.toggle('matrix',x.dataset.mode==='matrix');paint()}}));document.addEventListener('keydown',e=>{{if(e.key!=='ArrowDown'&&e.key!=='ArrowUp')return;const i=cards.indexOf(document.activeElement);if(i<0)return;e.preventDefault();const n=(i+(e.key==='ArrowDown'?1:-1)+cards.length)%cards.length;cards[n].focus();select(cards[n].dataset.lens)}});paint()}})();</script></body></html>'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path, help="run root containing manifest.json")
    parser.add_argument("--output", type=Path, help="output HTML (default: ROOT/gallery/index.html)")
    args = parser.parse_args()
    root = args.root.expanduser().resolve()
    output = (
        args.output.expanduser().resolve()
        if args.output
        else (root / "gallery" / "index.html").resolve()
    )
    if not output.is_relative_to(root):
        raise SystemExit("error: output must remain below the run root")
    if output.suffix.lower() != ".html":
        raise SystemExit("error: output must be an HTML file")
    try:
        data = load_manifest(root)
        concepts = validate(root, data)
    except ContractError as exc:
        raise SystemExit(f"error: {exc}") from exc
    concepts_root = (root / "concepts").resolve()
    if output.is_relative_to(concepts_root):
        raise SystemExit("error: output must not be inside the concepts directory")
    if any(output == (root / concept["entry"]).resolve() for concept in concepts if concept["entry"]):
        raise SystemExit("error: output must not replace a concept entry")
    if output.exists():
        if not output.is_file():
            raise SystemExit("error: output exists and is not a regular file")
        with output.open("r", encoding="utf-8", errors="replace") as existing:
            if GALLERY_MARKER not in existing.read(4096):
                raise SystemExit("error: refusing to replace a file not generated by design-frontier-gauntlet")
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(render(root, output, data, concepts), encoding="utf-8")
    except OSError as exc:
        raise SystemExit(f"error: gallery output cannot be written: {exc.strerror or type(exc).__name__}") from exc
    print(f"gallery: {output}")
    print(f"concepts: {sum(c['status'] == 'ready' for c in concepts)} ready, {sum(c['status'] == 'unavailable' for c in concepts)} unavailable")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
