# Layered Doctrine — Index

**Phase 6 shipped 2026-05-15** (INSPR-189). Auto-loaded budget reduced from ~127 k chars to ≤25 k. Kernel-only auto-load + on-demand domain packs via slash commands.

Phase 4 (synthesized 2026-05-14) produced **521 canonical rules across 12 layer files** from 556 Phase-2 raw rules with 35 Phase-3 cluster collapses. Phase 6 (2026-05-15) carved those into a kernel + 5 domain packs (17 layer files total) **without adding new rules** — same 521 entries, optimized distribution for on-demand loading. CORE.md and PROFILE-MARKUS.md remain on-demand-only.

## Decision provenance

- **B1 — topic renames**: 47 `_other:*` topics → canonical (39 accept-as-proposed + 7 explicit overrides + `migration`/`migrations` both → `process/migrations`); affects 11 rules whose canonical slots moved.
- **B2 — pure duplicates**: 13 clusters collapsed via 4 patterns (A: same-meta, B: scope→universal, C: priority→hard, D: role→universal).
- **B3 — scope divergences**: 9 clusters collapsed → `scope=universal` (broader wins).
- **B4 — aspect overlaps**: 10 clusters collapsed (6 plain merges + 4 merge-broaden with explicit synthesized assertions; the synthesized 4 are tagged `synthesized 2026-05-14 (Phase 4 broadening)` in provenance).

## Files

### Auto-loaded by CLAUDE.md (always-on)

| File | Scope tag | Loaded as | Description |
|---|---|---|---|
| **AGENTS-KERNEL.md** | `kernel` | `@./doctrine/docs/AGENTS-KERNEL.md` in every CLAUDE.md | **NEW (Phase 6)** — universal hard-safety + identity + slash-command router. ≤10 k chars. The ONLY auto-loaded doctrine post-Phase-6. |
| **`<repo>/AGENTS.md`** | `repo:*` | `@./AGENTS.md` in every CLAUDE.md | Per-repo delta (nixcfg / fleetcom / inspr). |

### On-demand domain packs (loaded by slash commands, Phase 6 NEW)

| Pack | Loaded by | Description |
|---|---|---|
| AGENTS-DOMAIN-DEV.md | `/dev` | Git workflow depth, build/test gates, code style, dev tooling |
| AGENTS-DOMAIN-SECRETS.md | `/secrets`, `/incident` | agenix pipeline, env-file pattern, 1P CLI, secret-leak protocol |
| AGENTS-DOMAIN-NIX.md | `/nix` | nix-darwin, Home Manager, devenv, NixOS modules + activation |
| AGENTS-DOMAIN-OPS.md | `/ops` | Fleet ops, SSH matrix, infra, tailscale, fleet-state |
| AGENTS-DOMAIN-PPM.md | `/ppm` | Paimos CLI, ticket conventions, project landscape, API endpoints |
| AGENTS-DOMAIN-IAC.md | `/iac` | L5 service config (Terraform for Zitadel/Cloudflare/GitHub/Headscale + inspr-services repo) |

### On-demand reference / role overlays

| File                                | Scope tag             | Rules | Loaded by                                   | Description                                                                                              |
| ----------------------------------- | --------------------- | ----- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| AGENTS-CORE.md                      | `universal`           | 199   | exhaustive ref (rarely loaded directly)     | **Pre-Phase-6 always-loaded file** (64 k chars). Now reference-only; the kernel + domain packs cover the actively-needed subset. |
| AGENTS-PROFILE-MARKUS.md            | `profile:markus`      | 153   | `/style`                                    | Full Markus profile — style, pacing, tooling depth beyond kernel's identity minimum.                     |
| AGENTS-AGENT-SYSOP.md               | `agent:sysop`         | 34    | `/ops`                                      | SYSOP role overlay — fleet-wide system operations.                                                       |
| AGENTS-AGENT-SYSOP-GB.md            | `agent:sysop-gb`      | 20    | (Gerhard's `/ops` variant)                  | SYSOP-GB role overlay — Greenbox-restricted ops.                                                         |
| AGENTS-AGENT-OPENCLAW-OPS.md        | `agent:openclaw-ops`  | 12    | `/ocbots` (nixcfg-only)                     | OPENCLAW-OPS role overlay — Open Clearance Workspace.                                                    |
| AGENTS-AGENT-FLEET-DECISION.md      | `agent:fleet-decision`| 10    | (cross-fleet decision agents)               | FLEET-DECISION role overlay — cross-fleet decision agents.                                               |
| AGENTS-AGENT-PPM.md                 | `agent:ppm`           | 6     | `/ppm`                                      | PPM role overlay — Paimos Project Manager API agents.                                                    |
| AGENTS-AGENT-PPM-READONLY.md        | `agent:ppm-readonly`  | 4     | `/ppm` (read-only mode)                     | PPM read-only overlay — audit / discovery only.                                                          |
| AGENTS-AGENT-DEV.md                 | `agent:dev`           | 2     | `/dev`                                      | DEV role overlay — development-oriented agents.                                                          |
| `nixcfg/AGENTS.md`                  | `repo:nixcfg`         | 55    | auto via per-repo CLAUDE.md @-ref           | nixcfg repo-specific delta (Nix darwin + Home Manager, NixOS host quirks, PII rule).                     |
| `fleetcom/AGENTS.md`                | `repo:fleetcom`       | 26    | auto via per-repo CLAUDE.md @-ref           | fleetcom repo-specific delta (FleetCom API + deploy + project IDs).                                      |
| `inspr/AGENTS.md`                   | `repo:inspr`          | 0     | auto via per-repo CLAUDE.md @-ref           | inspr meta-repo delta (umbrella initiative root; 0-rule overlay by design).                              |

**Phase-4 baseline rule count: 521 canonical rules** (Phase 4 synthesis, 2026-05-14) — every rule lands in exactly one Phase-4 layer. Phase 6 (2026-05-15) carved CORE into kernel + 5 domain packs WITHOUT adding new rules; the same 521 entries are now distributed across more files, optimized for on-demand loading.

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

> **SUPERSEDED by Phase 6 (2026-05-15).** The CLAUDE.md loader described below cascade-loaded CORE + PROFILE-MARKUS (~407 rules in context per session, ~127 k chars) and triggered Claude Code's >40 k performance warning. Phase 6 replaced this with a kernel-only auto-load + on-demand domain packs. Kept here for historical context only — see the Phase 6 section below for the current loader pattern.

Phase-5 QA surfaced that the per-repo `CLAUDE.md` symlinks → `AGENTS.md` (thin overlay) did **not** pull upstream rules into Claude Code's session context — markdown URL pointers are static text, not auto-fetched. **Fix (now superseded)**: vendored inspr-modules as a `git submodule` at `./doctrine/` in each consuming repo, replaced each `CLAUDE.md` symlink with a real file containing `@-refs` that cascade-load the layered files (`@./doctrine/docs/AGENTS-CORE.md`, `@./doctrine/docs/AGENTS-PROFILE-MARKUS.md`, `@./AGENTS.md`). Slash commands (`/ops`, `/ocbots`, `/oc-modelupdate`) likewise updated to `@-ref` their applicable role overlay (`AGENTS-AGENT-SYSOP.md`, etc.) so role rules load on demand. Empirically verified — Claude Code's @-ref behavior is documented (5-hop transitive include, relative paths from file location).

Per-repo loader commits:

| Commit | Repo | What |
|---|---|---|
| `adc2bf5f` | nixcfg | submodule + CLAUDE.md @-ref loader + 3 slash-cmd role overlay refs |
| `a2ea35a` | fleetcom | submodule + CLAUDE.md @-ref loader |
| `baa41e7` | inspr | submodule + CLAUDE.md @-ref loader |
| `9f3870a` | inspr-modules | CLAUDE.md @-ref loader (no submodule — IS the upstream) |

After this fix: a fresh Claude session in nixcfg loads ~407 rules in context (199 universal + 153 markus profile + 55 nixcfg-specific) instead of the 55 it had between Phase 5.2 and Phase 5.QA1.

## Phase 6 — Doctrine kernel + domain-pack tiering (SHIPPED 2026-05-15, INSPR-189)

Day-12's auto-loaded doctrine triggered Claude Code's >40k char performance warning per session in nixcfg (CORE 64k + PROFILE-MARKUS 47k). **Phase 6 shipped 2026-05-15**:

- **Kernel** (`AGENTS-KERNEL.md`, ~10 k) — always-on, replaces CORE+PROFILE in CLAUDE.md auto-load
- **Domain packs** (`AGENTS-DOMAIN-{DEV,SECRETS,NIX,OPS,PPM}.md`, ~5–10 k each) — NEW, loaded on demand by slash commands
- **Slash commands** (`/dev /secrets /nix /ops /ppm /style /incident /inspr`) — each `@-ref`s its target pack(s)
- **CORE.md and PROFILE-MARKUS.md** preserved for exhaustive reference (load via `/style` or direct Read); not auto-loaded

Result: nixcfg session opens with **≤25 k chars** (kernel + nixcfg/AGENTS.md) instead of ~127 k. >80 % reduction. >40 k warning gone.

The transitional INSPR-190 startup-hint rule (added 2026-05-15 morning, tagged sunset 2026-06-15) was DROPPED in this Phase 6 commit because the kernel router supersedes it.

### Phase 6 commits

| Commit | Repo | What |
|---|---|---|
| _(this commit)_ | inspr-modules | NEW AGENTS-KERNEL.md + 5 NEW AGENTS-DOMAIN-*.md + 5 NEW slash commands (dev, secrets, nix, style, incident) + CLAUDE.md → kernel-only loader + AGENTS-CORE.md drop transitional startup-hint topic + commands/inspr.md updated + AGENTS-INDEX rewrite |
| _(per-repo)_ | nixcfg, fleetcom, inspr | doctrine bump + CLAUDE.md → kernel-only loader + new slash-command symlinks |

### Provenance footers (historical citations — not live links)

Every rule in the layer files carries a `*<sub>src: …</sub>*` provenance footer. These are **point-in-time citations from Phase 2 extraction (2026-05-14)** — they record where the rule was found in the source tree at extraction time. Two consequences worth knowing:

- **Refs to `~/Code/nixcfg/+agents/rules/AGENTS.md`** point at a file deleted by Phase 5.2 (the canonical content moved to root `nixcfg/AGENTS.md` + this directory). 74 such refs across CORE, PROFILE-MARKUS, and the nixcfg overlay. To research a rule's original wording, use `git show <pre-2026-05-14-commit>:+agents/rules/AGENTS.md` (the file is preserved in git history forever).
- **Refs to SYSOP.md / SYSOP-GB.md with line numbers** target files that still exist but were trimmed by Phase 5.3 — line numbers have drifted (~59 refs). To find the original line, use `git log --follow -p +agents/rules/SYSOP.md` and search for the rule excerpt at the extraction commit.

Future provenance regeneration (re-run `synthesize.py` against current source files) is a deferred follow-up — the historical citations are intentionally preserved as-is to maintain extraction lineage.
