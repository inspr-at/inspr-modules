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

## Phase 5 migration: COMPLETED 2026-05-14

Phase 5 shipped end-to-end. Per-step commit refs:

| Step | Commit | Repo | What |
|---|---|---|---|
| 5.1 | `e7a79d2` | inspr-modules | canonical files land in `docs/` |
| 5.2 | `ab4c587d` | nixcfg | `AGENTS.md` → root real file (topology inversion) |
| 5.3 | `ceaf7cb7` | nixcfg | `+agents/rules/SYSOP{,-GB}.md` trimmed to operational reference (rule sections moved upstream) |
| 5.4 | `589cc6f` | fleetcom | `AGENTS.md` layered header + Secret-Safety dup retired |
| 5.5 | `c288cb9` | inspr | `AGENTS.md` marker (intentional 0-rule overlay) |
| 5.6 | `55415c6a` | nixcfg | cross-ref sweep (4 slash-cmd files + 2 broken symlinks + `+agents/README.md` rewrite) |

### Phase 5.QA1 — Loader follow-up (2026-05-14, post-QA)

Phase-5 QA surfaced that the per-repo `CLAUDE.md` symlinks → `AGENTS.md` (thin overlay) did **not** pull upstream rules into Claude Code's session context — markdown URL pointers are static text, not auto-fetched. **Fix**: vendored inspr-modules as a `git submodule` at `./doctrine/` in each consuming repo, replaced each `CLAUDE.md` symlink with a real file containing `@-refs` that cascade-load the layered files (`@./doctrine/docs/AGENTS-CORE.md`, `@./doctrine/docs/AGENTS-PROFILE-MARKUS.md`, `@./AGENTS.md`). Slash commands (`/ops`, `/ocbots`, `/oc-modelupdate`) likewise updated to `@-ref` their applicable role overlay (`AGENTS-AGENT-SYSOP.md`, etc.) so role rules load on demand. Empirically verified — Claude Code's @-ref behavior is documented (5-hop transitive include, relative paths from file location).

Per-repo loader commits:

| Commit | Repo | What |
|---|---|---|
| `adc2bf5f` | nixcfg | submodule + CLAUDE.md @-ref loader + 3 slash-cmd role overlay refs |
| `a2ea35a` | fleetcom | submodule + CLAUDE.md @-ref loader |
| `baa41e7` | inspr | submodule + CLAUDE.md @-ref loader |
| `9f3870a` | inspr-modules | CLAUDE.md @-ref loader (no submodule — IS the upstream) |

After this fix: a fresh Claude session in nixcfg loads ~407 rules in context (199 universal + 153 markus profile + 55 nixcfg-specific) instead of the 55 it had between Phase 5.2 and Phase 5.QA1.

### Provenance footers (historical citations — not live links)

Every rule in the layer files carries a `*<sub>src: …</sub>*` provenance footer. These are **point-in-time citations from Phase 2 extraction (2026-05-14)** — they record where the rule was found in the source tree at extraction time. Two consequences worth knowing:

- **Refs to `~/Code/nixcfg/+agents/rules/AGENTS.md`** point at a file deleted by Phase 5.2 (the canonical content moved to root `nixcfg/AGENTS.md` + this directory). 74 such refs across CORE, PROFILE-MARKUS, and the nixcfg overlay. To research a rule's original wording, use `git show <pre-2026-05-14-commit>:+agents/rules/AGENTS.md` (the file is preserved in git history forever).
- **Refs to SYSOP.md / SYSOP-GB.md with line numbers** target files that still exist but were trimmed by Phase 5.3 — line numbers have drifted (~59 refs). To find the original line, use `git log --follow -p +agents/rules/SYSOP.md` and search for the rule excerpt at the extraction commit.

Future provenance regeneration (re-run `synthesize.py` against current source files) is a deferred follow-up — the historical citations are intentionally preserved as-is to maintain extraction lineage.
