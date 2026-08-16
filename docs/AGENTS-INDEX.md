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
| **AGENTS-KERNEL.md** | `kernel` | `@./doctrine/docs/AGENTS-KERNEL.md` in every CLAUDE.md | **NEW (Phase 6)** — universal hard-safety + identity + slash-command router. Budget ≤12 000 bytes (`wc -c`; enforced by `inspr check`) — see § "The budget is 12 000 BYTES" below. The ONLY auto-loaded doctrine post-Phase-6. |
| **`<repo>/AGENTS.md`** | `repo:*` | `@./AGENTS.md` in every CLAUDE.md | Per-repo delta (nixcfg / inspr / amt-com / ops). |

### On-demand domain packs (loaded by slash commands, Phase 6 NEW)

| Pack | Loaded by | Description |
|---|---|---|
| AGENTS-DOMAIN-DEV.md | `/dev` | Git workflow depth, build/test gates, code style, dev tooling |
| AGENTS-DOMAIN-SECRETS.md | `/secrets`, `/incident` | agenix pipeline, env-file pattern, 1P CLI, secret-leak protocol |
| AGENTS-DOMAIN-NIX.md | `/nix` | nix-darwin, Home Manager, devenv, NixOS modules + activation |
| AGENTS-DOMAIN-OPS.md (private) | `/ops` | Fleet ops, SSH matrix, infra, tailscale, fleet-state |
| AGENTS-DOMAIN-PPM.md (private) | `/ppm` | Paimos CLI, ticket conventions, project landscape, API endpoints |
| AGENTS-DOMAIN-IAC.md (private) | `/iac` | L5 service config (Terraform for Zitadel/Cloudflare/GitHub/Headscale + inspr-services repo) |

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
| `fleetcom/AGENTS.md`                | `repo:fleetcom`       | 26    | auto via per-repo CLAUDE.md @-ref           | fleetcom repo-specific delta (archived tool — superseded by Pharos).                                      |
| `inspr/AGENTS.md`                   | `repo:inspr`          | 0     | auto via per-repo CLAUDE.md @-ref           | inspr meta-repo delta (umbrella initiative root; 0-rule overlay by design).                              |

**Phase-4 baseline rule count: 521 canonical rules** (Phase 4 synthesis, 2026-05-14) — every rule lands in exactly one Phase-4 layer. Phase 6 (2026-05-15) carved CORE into kernel + 5 domain packs WITHOUT adding new rules; the same 521 entries are now distributed across more files, optimized for on-demand loading.

## Repository architecture — the atelier pattern

_Added 2026-08-16 after an agent misread it three times in one session._

**Read this before drawing any conclusion about a repository's visibility.**

INSPR repositories come in two kinds, and confusing them produces confident,
wrong recommendations:

| Kind | What it is | Visibility | Examples |
|---|---|---|---|
| **Atelier** | A shared **library** of identity-free primitives, published so anyone can consume the same building blocks the fleet uses | **public by design** | `inspr-modules` |
| **Studio** | A **context flake** supplying identity-specific values — hosts, keys, instances, preferences — on top of an atelier | private | `nixcfg`, family flakes, future paid-product flakes |

The atelier's own `flake.nix` states the mission: *"democratize software dev by
letting anyone consume the same primitives Markus uses on his own fleet."* Its
modules are built to match — `ssh-authorized` takes a key map as a parameter,
`git-identity` takes identities, and `paimos-config` is documented as
materialising instance routing **without credentials**.

### The failure this prevents

🔴 **Public content in an atelier is the design, not a leak.**

The trust-contexts rule — classify by ownership of the output, personal / INSPR /
augmentoring, never by GitHub org — is about *where work belongs*. It says
nothing about libraries, and applied alone it misclassifies an atelier: a public
repository holding fleet-shaped material reads as an accident when it is the
stated purpose.

On 2026-08-15/16 an agent applied exactly that lens to `inspr-modules`, concluded
the repository had been made public by mistake, and three separate times proposed
flipping it private. That would have broken the atelier pattern and the fleet at
once — nine load-bearing consumption points in `nixcfg` alone
(`ssh-authorized` ×14 across NixOS and Home Manager, `git-identity`,
`paimos-config`, `agent-secrets`, `agent-skills`, `devenv-direnv-fix`,
`git-atelier-credentials`, the `inspr` CLI package) — and it needed agenix
plumbing plus a `switch` on every machine to be possible at all.

The pattern was documented only in `README.md` and `flake.nix`. Neither is
auto-loaded, and neither is where anyone looks for a visibility question. That
omission, not the agent's reasoning, is why it took three attempts.

### The rule

- 🟡 **Before concluding anything about a repository's visibility, read its
  `flake.nix` header and `README.md`.** An atelier says what it is in the first
  three lines.
- 🟡 **An atelier must stay identity-free.** Content that cannot be parameterised
  — a fleet SSH matrix, an instance routing table, one person's working
  preferences — does not belong in one, whatever the repository's visibility.
- 🟡 **The correct fix for operator content in an atelier is to move the
  content, never to change the repository's visibility.** The library is
  load-bearing for consumers who are not you.

## Worktree placement

_Added 2026-08-16 after an audit found four competing conventions and none authoritative._

🟡 **Agent worktrees go in `.claude/worktrees/<slug>/` inside the repository.**

That path is already gitignored in wired repos, it travels with the checkout, it
is visible to anyone working there, and it cannot be mistaken for a sibling
repository in a file browser.

### Why the rule exists

An audit of `~/Code` on 2026-08-16 found worktrees placed four different ways,
because nothing said where they belonged:

| Placement | Live | Problem |
|---|---|---|
| `~/Code/<repo>-worktrees/` | 0 | Convention created, never used. Five empty directories survived it. |
| `/private/tmp/<name>.XXXX` | — | The directory dies on reboot; the registration does not. Four stale ones found, all `prunable`. |
| `~/Code/<repo>-<ticket>/` | 3 | Works, but looks like a duplicate repository in a file browser and never gets cleaned up. |
| `.claude/worktrees/<slug>/` | 1 | Correct. |

The `-worktrees` directories were the visible symptom: five empty shells whose
repositories registered their worktrees somewhere else entirely.
`paimos-worktrees` was empty while paimos's actual worktree sat in
`/private/tmp`; `amt-start-worktrees` was empty while amt-start's sat at
`~/Code/amt-start-test-triage`.

### Companion rules

- 🟡 **Two agents in one checkout will collide silently.** A `git checkout` moves
  the ground under the other; a `git add -A` sweeps up work in flight that was
  never yours. If two things are being worked on, that is two worktrees — and the
  coordinating agent is one of the two, not an exception to its own rule.
- 🟡 **Announce before acting in a tree you do not own.** One message, and it has
  prevented at least two collisions in a single day.
- 🟡 **Return the shared checkout to its default branch when you are done.** A
  tree left on a deleted branch costs the next session a confusing `git pull`
  failure. Cheap for you, expensive for them.
- 🟡 **`git worktree prune` after any run that used a temporary directory.** It
  removes only registrations whose directory is already gone, so it cannot touch
  live work.

## Where the operator packs went

_2026-08-16. INSPR-299._

This repository is a **public library flake** — see the atelier section above.
The operator-specific doctrine packs no longer live here, because a fleet SSH
matrix, an instance routing table and one person's working preferences have no
identity-free form and had no business in an atelier.

They are in **`inspr-at/inspr-doctrine-private`**, vendored by studio
repositories as a second submodule at `doctrine-private/` over SSH:

| Moved | Loaded by |
|---|---|
| `AGENTS-PROFILE-MARKUS.md` | `/style` |
| `AGENTS-DOMAIN-PPM.md` | `/ppm` |
| `AGENTS-DOMAIN-OPS.md` | `/ops`, `/incident` |
| `AGENTS-DOMAIN-IAC.md` | `/iac` |
| `AGENTS-AGENT-SYSOP{,-GB}.md` | `/ops` |
| `AGENTS-AGENT-PPM{,-READONLY}.md` | role overlays |
| `AGENTS-AGENT-FLEET-DECISION.md` | role overlay |
| `AGENTS-AGENT-OPENCLAW-OPS.md` | role overlay |

**The commands still work.** `/ppm`, `/ops`, `/iac`, `/style` and `/incident`
are unchanged from a consumer's point of view — they resolve through
`doctrine-private/commands/` instead of `doctrine/commands/`. A repository that
vendors only the public half simply does not have them, which is the intent:
`janus`, `paimos` and `pharos` get a baseline an outside contributor can act on.

`/incident` is deliberately **split** — it loads `DOMAIN-OPS` from the private
half and `DOMAIN-SECRETS` from this one, because the secrets pack is mostly
generic principles.

Staying here: `AGENTS-KERNEL`, `AGENTS-CORE`, `AGENTS-DOMAIN-{DEV,NIX,SECRETS}`,
`AGENTS-AGENT-DEV`, this index, and every Nix module, package and bundled skill.

## Kernel gatekeeper & size budget

_Moved out of `AGENTS-KERNEL.md` on 2026-07-26 — it is guidance for whoever **edits** the kernel, and was costing every agent context on every turn to serve a rare action._

**The kernel grows ONLY for**:

1. A new safety irreversible (would prevent immediate damage in turn 1)
2. A new global protocol change affecting every agent in every repo
3. A new slash command (router update)

Everything else — domain knowledge, role-specific rules, technique notes, style preferences — goes to a **domain pack**. Don't add a rule to the kernel that could live elsewhere. Default to a domain pack; promote to kernel only when the cost of NOT having it always-loaded exceeds the auto-load cost. When the kernel is near budget, prefer **merging into an adjacent bullet** over adding a new one.

### The budget is 12 000 BYTES

Measure with `wc -c`, not a character count — the 🔴/🟡 emoji are multibyte, so the two differ by ~130. Enforced by `inspr check` → `check_doctrine_kernel_size_budget` (`pkgs/inspr/inspr.sh`), which reads `$NIXCFG_DIR/doctrine/docs/AGENTS-KERNEL.md`.

Historical note: the kernel header long claimed a `≤ 10 000 chars` budget while the only enforcement was at 12 000 bytes. The two numbers were reconciled to 12 000 bytes in the 2026-07-26 audit.

### 2026-07-26 budget audit

Kernel went **9 997 → 7 334 bytes** with no rule lost. What changed:

- **Corrected 5 wrong router sizes.** The `Adds (~chars)` column understated `/style` (20k → actual 46k), `/incident` (5k → 20k), `/ppm` (8k → 22k), `/ops` (12k → 18k), `/dev` (8k → 11k). Replaced the per-row column with a single "heavy ones" line — accurate and far cheaper to maintain.
- **Removed 6 🟡 rules that violated the gatekeeper** and were already duplicated in packs: `gh pr view/diff`, push-is-normal-flow, the multi-agent stash recipe, `git config --global` (all in `/dev`), and the PPM keyring paragraph (`/ppm` covers it far better). `zellij, NOT tmux` existed only in the 46k `PROFILE-MARKUS`, so it was added to `/dev` rather than dropped.
- **Moved meta out**: this gatekeeper section, the cross-reference footer, and the per-repo-deltas paragraph. ~20 % of the kernel was describing itself.
- **Deduplicated**: the kernel's purpose was stated three times (subtitle, intro, gatekeeper closing) — now once. The secret-read prohibition was stated twice — now folded into one bullet with the positive `[ -n "$VAR" ]` check.
- **Compacted** the time-awareness bullet (416 → ~190 bytes) and trimmed the env-dump example list, which had grown long enough to undercut its own "apply the principle, not the literal list" instruction.

**Stale scope fixed**: the kernel header listed its consumers as "nixcfg, inspr, fleetcom, inspr-modules" — omitting `ops` and naming `fleetcom`, which the kernel body itself declares archived.

### 2026-07-26 second sweep — kernel 7 334 → 5 494 bytes

A follow-up pass over the **combined** auto-load surface (kernel + per-repo delta), not just the kernel:

- **Router 1 713 → 739.** The table's "If you're about to… Edit nix-darwin / Home Manager / devenv / NixOS module → `/nix`" prose became a compact `·`-separated line. Same routing signal, ~1 000 bytes cheaper. The per-pack size warning stayed, since it is the part agents actually need before loading.
- **Editor-facing meta 1 168 → 353.** The HTML preamble and the Gatekeeper stub are addressed to whoever *edits* the kernel; the full text already lives here. Every agent was paying for it on every turn.
- **Identity & protocol compressed** — Style / Pacing / Time / Default kept, said shorter. Trust-contexts keeps the 🔴 crossing rule inline and points at the guidelines for classification detail.
- **Cross-linked two guidelines describing the same split on different axes**: INSPR `trust-contexts` (repos and code) ↔ INSPR `domain-separation-barta-vs-augmentoring` (domains and services). Neither had referenced the other.

**Per-repo delta, nixcfg**: `AGENTS.md` 21 291 → 6 003 in the first pass (host rules → OPS runbooks, dead provenance dropped), then split so Claude stops reading the kernel twice — see below.

**The mirror was being read twice.** `CLAUDE.md` loads the kernel *and* `AGENTS.md`, which contained a 1 488-byte paraphrase of the kernel for tools that do not follow `@-ref`s. nixcfg now splits them: `AGENTS-NIXCFG.md` holds the repo delta and is what `CLAUDE.md` loads; `AGENTS.md` keeps the 🔴 mirror plus a pointer, for Cursor / Aider / OpenCode / Codex CLI. No generated file and no sync burden — the delta exists once.

**Also relocated to PPM**: the agenix rekey recovery procedure and setup facts → NIX runbook `agenix-rekey-safety` (#3707). The 🔴 *detection* rule (578-byte marker, `git diff --stat` before commit) stays in the repo, because it has to be visible without loading anything.

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

Phase-5 QA surfaced that the per-repo `CLAUDE.md` symlinks → `AGENTS.md` (thin overlay) did **not** pull upstream rules into Claude Code's session context — markdown URL pointers are static text, not auto-fetched. **Fix (now superseded)**: vendored inspr-modules as a `git submodule` at `./doctrine/` in each consuming repo, replaced each `CLAUDE.md` symlink with a real file containing `@-refs` that cascade-load the layered files (`@./doctrine/docs/AGENTS-CORE.md`, `@./doctrine/docs/AGENTS-PROFILE-MARKUS.md`, `@./AGENTS.md`). Slash commands (`/ops`, `/ocbots`, `/oc-modelupdate`) likewise updated to `@-ref` their applicable role overlay (`AGENTS-AGENT-SYSOP.md` (private), etc.) so role rules load on demand. Empirically verified — Claude Code's @-ref behavior is documented (5-hop transitive include, relative paths from file location).

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

Result: nixcfg session opens with **~30 k** (kernel + nixcfg/AGENTS.md) instead of ~127 k. >75 % reduction, >40 k warning gone.

> ⚠️ **Corrected 2026-07-26.** This line originally claimed ≤25 k. Measured: `inspr` 13.6 k ✓, `ops` 23.7 k ✓, but **nixcfg 30.4 k ✗** — the kernel got disciplined, the per-repo delta did not. nixcfg's `AGENTS.md` alone is ~20.8 k (the 55 Phase-4 synthesized rules) and is now the binding constraint, not the kernel. Trimming it is tracked separately.

The transitional INSPR-190 startup-hint rule (added 2026-05-15 morning, tagged sunset 2026-06-15) was DROPPED in this Phase 6 commit because the kernel router supersedes it.

### Phase 6 commits

| Commit | Repo | What |
|---|---|---|
| _(this commit)_ | inspr-modules | NEW AGENTS-KERNEL.md + 5 NEW AGENTS-DOMAIN-*.md + 5 NEW slash commands (dev, secrets, nix, style, incident) + CLAUDE.md → kernel-only loader + AGENTS-CORE.md drop transitional startup-hint topic + commands/inspr.md updated + AGENTS-INDEX rewrite |
| _(per-repo)_ | nixcfg, fleetcom, inspr, amt-com | doctrine bump + CLAUDE.md → kernel-only loader + new slash-command symlinks |

### Provenance footers (historical citations — not live links)

Every rule in the layer files carries a `*<sub>src: …</sub>*` provenance footer. These are **point-in-time citations from Phase 2 extraction (2026-05-14)** — they record where the rule was found in the source tree at extraction time. Two consequences worth knowing:

- **Refs to `~/Code/nixcfg/+agents/rules/AGENTS.md`** point at a file deleted by Phase 5.2 (the canonical content moved to root `nixcfg/AGENTS.md` + this directory). 74 such refs across CORE, PROFILE-MARKUS, and the nixcfg overlay. To research a rule's original wording, use `git show <pre-2026-05-14-commit>:+agents/rules/AGENTS.md` (the file is preserved in git history forever).
- **Refs to SYSOP.md / SYSOP-GB.md with line numbers** target files that still exist but were trimmed by Phase 5.3 — line numbers have drifted (~59 refs). To find the original line, use `git log --follow -p +agents/rules/SYSOP.md` and search for the rule excerpt at the extraction commit.

Future provenance regeneration (re-run `synthesize.py` against current source files) is a deferred follow-up — the historical citations are intentionally preserved as-is to maintain extraction lineage.
