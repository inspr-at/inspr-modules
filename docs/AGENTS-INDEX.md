# Phase 4 Layered Doctrine — Index

Synthesized 2026-05-14 from 556 Phase-2 raw rules with 35 Phase-3 cluster collapses → 521 canonical rules across 12 layer files.

## Decision provenance

- **B1 — topic renames**: 47 `_other:*` topics → canonical (39 accept-as-proposed + 7 explicit overrides + `migration`/`migrations` both → `process/migrations`); affects 11 rules whose canonical slots moved.
- **B2 — pure duplicates**: 13 clusters collapsed via 4 patterns (A: same-meta, B: scope→universal, C: priority→hard, D: role→universal).
- **B3 — scope divergences**: 9 clusters collapsed → `scope=universal` (broader wins).
- **B4 — aspect overlaps**: 10 clusters collapsed (6 plain merges + 4 merge-broaden with explicit synthesized assertions; the synthesized 4 are tagged `synthesized 2026-05-14 (Phase 4 broadening)` in provenance).

## Files

| File | Scope tag | Rules | Target deployment path | Description |
|---|---|---|---|---|
| AGENTS-CORE.md | `universal` | 199 | inspr-modules/docs/AGENTS-CORE.md | Universal rules — apply to every Claude agent regardless of role/profile/repo. |
| AGENTS-PROFILE-MARKUS.md | `profile:markus` | 153 | inspr-modules/docs/AGENTS-PROFILE-MARKUS.md | Markus Barta's personal preferences (style, pacing, tooling). |
| AGENTS-AGENT-SYSOP.md | `agent:sysop` | 34 | inspr-modules/docs/AGENTS-AGENT-SYSOP.md | SYSOP role overlay — fleet-wide system operations. |
| AGENTS-AGENT-SYSOP-GB.md | `agent:sysop-gb` | 20 | inspr-modules/docs/AGENTS-AGENT-SYSOP-GB.md | SYSOP-GB role overlay — Greenbox-restricted ops. |
| AGENTS-AGENT-OPENCLAW-OPS.md | `agent:openclaw-ops` | 12 | inspr-modules/docs/AGENTS-AGENT-OPENCLAW-OPS.md | OPENCLAW-OPS role overlay — Open Clearance Workspace. |
| AGENTS-AGENT-FLEET-DECISION.md | `agent:fleet-decision` | 10 | inspr-modules/docs/AGENTS-AGENT-FLEET-DECISION.md | FLEET-DECISION role overlay — cross-fleet decision agents. |
| AGENTS-AGENT-PPM.md | `agent:ppm` | 6 | inspr-modules/docs/AGENTS-AGENT-PPM.md | PPM role overlay — Paimos Project Manager API agents. |
| AGENTS-AGENT-PPM-READONLY.md | `agent:ppm-readonly` | 4 | inspr-modules/docs/AGENTS-AGENT-PPM-READONLY.md | PPM read-only overlay — audit/discovery only. |
| AGENTS-AGENT-DEV.md | `agent:dev` | 2 | inspr-modules/docs/AGENTS-AGENT-DEV.md | DEV role overlay — development-oriented agents. |
| nixcfg-AGENTS.md.template | `repo:nixcfg` | 55 | nixcfg/AGENTS.md | nixcfg repo-specific delta (Nix darwin + Home Manager). |
| fleetcom-AGENTS.md.template | `repo:fleetcom` | 26 | fleetcom/AGENTS.md | fleetcom repo-specific delta (fleet management CLI). |
| inspr-AGENTS.md.template | `repo:inspr` | 0 | inspr/AGENTS.md | inspr meta-repo delta (umbrella initiative root). |

**Total canonical rules across all layers: 521**
(equals 521 canonical entries — every rule lands in exactly one layer.)

## Layer-file format conventions

- Topics within a layer follow a LOGICAL order: security → incident-response → secrets → style → tools → process → workflow → pacing → git → nix/nixos → infra → agent-identity → other (alphabetical tail).
- Within each topic, rules sort by priority: 🔴 HARD → 🟡 STRONG → 🟢 SOFT.
- Every rule carries provenance (source path + line range, plus `incident_link` if any) and an HTML-comment trailer with the contributing `rule_ids` + `cluster` id so Phase 5 tooling can verify the mapping.
- Merged rules list ALL contributing sources in provenance (not just newest).
- The 4 `merge-broaden` rules from B4 also carry the synthesis note in their provenance line.

## Phase 5 migration plan (preview)

Phase 5 will (a) copy `AGENTS-CORE.md` + `AGENTS-PROFILE-MARKUS.md` + all `AGENTS-AGENT-*.md` files into `inspr-modules/docs/`; (b) replace each repo's root `AGENTS.md` with the corresponding `<repo>-AGENTS.md.template` from this staging directory (renaming the file to `AGENTS.md` and dropping the `.template` suffix); and (c) wire the `tools/inspr-doctor` checker to verify every live `AGENTS.md` references the canonical inspr-modules links and that no orphan rules remain in the per-repo files.
