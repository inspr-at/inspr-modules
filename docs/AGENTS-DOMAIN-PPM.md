# AGENTS — Domain: PPM

*Layer: `domain:ppm` · INSPR-189 Phase 6 · Loaded on demand by `/ppm`.*

Detailed rules for Paimos/PPM ticket work: `paimos` CLI, ticket conventions, project landscape, API endpoints, time tracking, status states. Kernel covers secret-handling side ("source the env, never cat"). This pack adds workflow depth.

**Load before**: any ticket work — create/update/query, time-tracking, ticket-aware automation. Pair with `/dev` when commits/PRs reference tickets.

---

## Auth

Two auth surfaces — DON'T conflate them:

**1. `paimos` CLI** — uses macOS Keychain (entry `paimos-cli/<instance>`) on macOS, Secret Service / KWallet on Linux, Credential Manager on Windows. Seeded once per host via `paimos auth login` at the keyboard. Verify with `paimos auth whoami`. Headless / CI fallback: set `PAIMOS_API_KEY` env-var (overrides keyring lookup).

- 🟡 **Onboarding new macOS host**: run `paimos auth login` interactively at the iMac/Mac keyboard (not over SSH — Keychain access is unreliable from non-GUI sessions). Pre-fill with `--api-key "$PPMAPIKEY"` to skip the prompt if the env-file is already in place:
  ```bash
  bash -lc 'set -a; . ~/.inspr/secrets/agents/PPMAPIKEY.env; set +a; paimos auth login --url https://pm.barta.cm --api-key "$PPMAPIKEY" --name ppm'
  ```
- 🟡 After `paimos auth login`, daily invocation is just `paimos <subcommand>` — no env-file sourcing needed; Keychain is authoritative.
- 🟡 `paimos auth whoami` is the canonical smoke. inspr-doctor checks this (INSPR-193).
- 🔴 Sourcing `PPMAPIKEY.env` does NOT auth the paimos CLI — it only sets `$PPMAPIKEY`, which paimos ignores (it looks at `$PAIMOS_API_KEY`). The two env-var names are deliberately different (env-file convention = filename-as-varname; paimos's convention = `PAIMOS_API_KEY`).

**2. Raw `curl` against `pm.barta.cm/api/...`** — uses the env-file. Source it, use `$PPMAPIKEY` in the `Authorization: Bearer` header.

```bash
( set -a; source ~/.inspr/secrets/agents/PPMAPIKEY.env; \
  curl -H "Authorization: Bearer $PPMAPIKEY" https://pm.barta.cm/api/projects/4/issues; \
  set +a )
```

- 🔴 NEVER `cat`, `head`, `tail`, `Read`, or print the env file. Verify presence with `ls -la` only.
- 🔴 Never put secrets, API tokens, or credentials in ticket descriptions or notes; they stay in agenix.

See `/secrets` for full secret-handling pipeline.

### Stuck? "I can't find PPM creds"

Run this diagnostic chain top-to-bottom — first thing that fails points at the fix:

```bash
ls ~/.inspr/secrets/agents/         # are the env-files materialized on this host?
paimos auth whoami                  # is Keychain seeded? (prints user on success)
paimos doctor                       # full health report
~/Code/inspr/scripts/inspr-doctor.sh --verbose   # canonical fleet-wide onboarding check
```

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `PPMAPIKEY.env` missing | secrets not materialized on this host | enable `inspr.secrets.agents` in HM, `home-manager switch` |
| `paimos auth whoami` exits 1 | Keychain not seeded | run the `paimos auth login` block above **at the keyboard**, not over SSH |
| `paimos auth whoami` exits 1 after key rotation | stale Keychain entry | re-run `paimos auth login` with the fresh key |
| `$PPMAPIKEY` empty after sourcing | wrong filename / variable | `PPMAPIKEY.env` exports `PPMAPIKEY` (env-file convention = filename-as-varname) |
| `curl` returns 401 | wrong header / stale key | `Authorization: Bearer $PPMAPIKEY` (not `Token`); confirm key not rotated |
| Linux / headless / CI | no GUI keyring | use `PAIMOS_API_KEY=...` env-var fallback (overrides Keychain lookup) |

🔴 Never `cat`/`Read`/`head`/`tail` the .env files — `ls -la` only.

## Endpoints

- **One instance: PPM — `https://pm.barta.cm`.** Everything routes there; there is no second instance and no routing decision to make.
- Auth: `Authorization: Bearer $PPMAPIKEY` for raw curl; the `paimos` CLI reads Keychain.

🟡 The **PMO** instance (`pm.bytepoets.com`, the BYTEPOETS Paimos) was **decommissioned in June 2026** when Markus left BYTEPOETS. Its keys (`PMOAPIKEY`, `PMOURL`, `PMOSERVER*`) and the `pmo` entry in `~/.paimos/config.yaml` are gone. If you see `$PMOURL`, `paimos --instance pmo`, or a `~/Code/BYTEPOETS/ → PMO` routing rule anywhere, it's stale — it will 401. Flag it.

## Project key reference

Use the human-visible project key in chat, commits, branches, PR titles. Numeric DB id is for API calls only.

All projects live on PPM (`pm.barta.cm`) — there is no second instance.

| Key      | id | Project                         | Repo(s)             |
| -------- | -- | ------------------------------- | ------------------- |
| `INSPR`  | 8  | Umbrella initiative             | inspr               |
| `NIX`    | 1  | nixcfg                          | nixcfg              |
| `PAI`    | 6  | Paimos (the OSS PM tool itself) | paimos, paimos-site |
| `PWEB`   | 7  | paimos.com                      | paimos-site         |
| `FLEET`  | 4  | FleetCom                        | fleetcom            |
| `DSC26`  | 2  | DSC Infrastructure              | dsccfg              |
| `OPS`    | 14 | Operations                      | inspr, nixcfg       |
| `HAUSV`  | 21 | WEG Portal (hausv.org)          | hausv-org           |
| `PHAROS` | 17 | Pharos                          | pharos              |
| `HOSTD`  | 20 | HostDash                        | hostdash            |
| `JANUS`  | 12 | JANUS                           | janus               |
| `PIXD`   | 13 | pixdcon                         | pixdcon             |
| `OPUSW`  | 18 | opusweb                         | opusweb             |
| `FUNK`   | 5  | funkeykid                       | funkeykid           |
| `SPELD`  | 19 | Spell Dream                     | spelldream          |
| `GSC26`  | 3  | Website gsc.co.at               | gsc                 |
| `AMTWEB` | 22 | Augmentoring Website            | amt-com             |
| `AMTCO`  | 16 | Augmentoring Content            | _(pending — David)_ |

🟡 **`DSC26` is personal, despite the `-26` suffix.** It's DSC Infrastructure (the `dsccfg` fleet). The suffix pattern-matched the old BYTEPOETS `BON26`/`MER26` keys, and doctrine mislabeled it "BYTEPOETS internal / PMO" until 2026-07-13. It's an ordinary PPM project.

🟡 **`AMTWEB` is not `AMTCO`.** AMTWEB = the augmentoring.com website relaunch (`amt-com` repo). AMTCO = Augmentoring content production. Keys sit one character apart and `paimos` accepts either interchangeably.

## Default behavior

- 🟡 Treat Paimos APIs as **read-only by default**. Stay at project-level for unfamiliar projects.

## Workflow: backing tickets

- 🟡 Before starting work, check PPM for a backing ticket. If none exists, create one first.
- 🟡 Do NOT create local backlog files (no `BACKLOG.md`, no `TODO.md`). Backlog management is in PPM.
- 🟡 Update PPM ticket status as work progresses: `new → in-progress → done`.
- 🔴 Mark PPM tickets as `done` only when acceptance criteria are met. "Done means done."
- 🟡 Always reference tickets by human-visible key (e.g. `FLEET-79`) in chat, commits, branches, PR titles.

## Workflow: time tracking

- 🟡 Start PPM timer when beginning work, stop when done. `mba` is `user_id 2`.
- 🟡 When work is done, update PPM ticket status AND stop the timer.

## Workflow: dedupe before creating

- 🟡 Before creating a PPM issue, search to dedupe via `GET /api/search?q=<topic>`.

## Workflow: GET-before-PUT

🟡 PPM PUT replaces the record **wholesale**. PATCH is silently ignored (no error, no effect).

```
1. GET /api/issues/<id>           # capture full restore-state
2. Verify ticket identity         # id + title match expectation
3. Mutate fields locally
4. PUT /api/issues/<id>           # full record, all fields
```

This rule is **non-negotiable**. PAI-313 contamination (2026-05-10) happened because someone PUT a partial body and wiped fields.

## API endpoint quirks

| Operation                   | Endpoint                              | Notes                                            |
| --------------------------- | ------------------------------------- | ------------------------------------------------ |
| Create issue in project     | `POST /api/projects/<id>/issues`      | `project_id` in URL, NOT body (body returns err) |
| Create sprint-only issue    | `POST /api/issues`                    | only without project_id                          |
| Update issue                | `PUT /api/issues/<id>`                | wholesale replace; PATCH silently ignored        |
| List issues in project      | `GET /api/projects/<id>/issues`       | `project_id` query param NOT honored on `/api/issues` |
| Search                      | `GET /api/search?q=<topic>`           | dedupe before create                             |

## Project repos — linking a project to its code

Repos are a **first-class entity** (`repo` in `/api/schema`), project-scoped — not an issue type and not a knowledge entry. A repo may be linked to more than one project (`paimos-site` sits under both `PAI` and `PWEB`); `sort_order` decides display order, so put the primary repo at `0`.

**`RepoInput`**: `url` required; `label`, `default_branch`, `sort_order` optional.

| Operation | Endpoint |
| --- | --- |
| List | `GET /api/projects/<id>/repos` (CLI: `paimos project repos <key>`) |
| Create | `POST /api/projects/<id>/repos` |
| Update | `PUT /api/projects/<id>/repos/<repo_id>` (wholesale — send all fields) |
| Delete | `DELETE /api/projects/<id>/repos/<repo_id>` |

- 🔴 **`POST` does not upsert.** POSTing a url that's already linked creates a **duplicate row with a new id**, silently. To change a label/branch/order, `PUT` the existing `repo_id` — never re-POST. (Learned 2026-07-13: a re-POST to PAI created a phantom third repo.)
- 🟡 **`PATCH` is silently ignored** on repos, same as issues — returns empty, changes nothing, exit 0. Use `PUT` with the full body.
- 🟡 The CLI is **read-only** here (`project repos` lists; there is no `repos add`). Writes go through `paimos curl <path> -X POST|PUT|DELETE --data '<json>'`.
- 🟡 Use the browsable **HTTPS** url (`https://github.com/markus-barta/<repo>`), not the `git-personal` SSH alias — the alias only resolves on Markus's machines, and PPM renders this as a link.

## Knowledge entries — the home for docs, architecture & durable knowledge

PPM **Knowledge** is the canonical home for knowledge that used to sprawl into `.md` files. **Kernel rule: knowledge/docs/architecture → a PPM Knowledge entry, not a new local doc.** Entries are **project-scoped**.

**What goes here**: architecture, design rationale, positioning, vision, playbooks, field notes, research write-ups, durable how-tos, integration/external-system notes, cross-project relationships.

**What stays a local `.md` (do NOT migrate)**: `README`, `AGENTS.md`/`CLAUDE.md` + doctrine packs (must auto-load offline — can't bootstrap from an L6 app), `RUNBOOK.md`, `CHANGELOG.md`, `RESUMING-*` session notes, `LICENSE`, code comments.

### Types (the `type` taxonomy)

| type | use for |
| --- | --- |
| `guideline` | architecture, design rationale, positioning, vision, playbooks, field notes, conventions — **catch-all** for durable reference knowledge |
| `runbook` | net-new operational how-tos that aren't host-bound (host `RUNBOOK.md` stays local) |
| `external_system` | integration knowledge for external services / APIs |
| `related_project` | cross-project relationships / links |
| `memory` | agent auto-memory (decay/staleness/reference-counted subsystem — PAI-347/349). Machine lane; don't hand-author. |

🟡 **Type-value gotcha**: the list-filter query enum is hyphenated (`?type=external-system`) but stored/path type values are underscored (`external_system`, `related_project`). Use **underscores** in the `{type}` path + create body; reach for hyphens only if a `?type=` filter rejects the underscore form. Verify on first use (greenfield as of 2026-05-28 — no entries existed yet).

### Endpoints (project-scoped)

| Operation | Endpoint |
| --- | --- |
| List (optionally filter) | `GET /api/projects/<id>/knowledge[?type=<type>]` |
| Create | `POST /api/projects/<id>/knowledge` (body: `KnowledgeEntryInput`) |
| Fetch one | `GET /api/projects/<id>/knowledge/<type>/<slug>` |
| Replace (rename via `body.slug`) | `PUT /api/projects/<id>/knowledge/<type>/<slug>` |
| Soft-delete (Trash) | `DELETE /api/projects/<id>/knowledge/<type>/<slug>` |

**`KnowledgeEntryInput`**: `slug` + `title` required; `type`, `body` (markdown content), `status`, `metadata` (free object) optional. Addressed by `(project, type, slug)`. Numeric project ids for API: see the `id` column in [Project key reference](#project-key-reference).

- 🟡 **Provenance convention**: put `metadata: { "source_repo": "inspr", "orig_path": "architecture.md", "tags": [...] }` so a migrated doc keeps a breadcrumb home.
- 🟡 PUT replaces **wholesale** (same as issues) — GET-before-PUT.
- 🟡 `memory` type has extra lifecycle endpoints (`.../memory/stale?days=`, `.../memory/proposed/stale?days=`, `POST .../memory/references`) — reserved for the auto-memory subsystem; ignore for hand-authored docs.

### Create example

```bash
( set -a; source ~/.inspr/secrets/agents/PPMAPIKEY.env
  curl -s -X POST -H "Authorization: Bearer $PPMAPIKEY" -H "Content-Type: application/json" \
    --data @/tmp/entry.json \
    https://pm.barta.cm/api/projects/8/knowledge
  set +a )
# /tmp/entry.json:
# {"type":"guideline","slug":"inspr-architecture","title":"INSPR Architecture",
#  "body":"# ...markdown...","metadata":{"source_repo":"inspr","orig_path":"architecture.md"}}
```

## Workflow: ticket sweeping

🟡 Sweep tickets need explicit time-boxing **at the per-item level**. Promote items past 30 min to their own focused tickets. **Promoting is a feature, not a failure** — better to have N focused tickets than one bloated sweep.

## Workflow: ticket as design-trail

- 🟡 When a design decision goes through many reorientations, capture the trail (what was tried/rejected and why) **in the ticket** so alternatives don't get re-litigated every session.
- 🟡 In multi-session agent workstreams, write a self-contained ticket (code/diffs/validation gates/rollback) and hand off rather than turn-taking.

## Workflow: ticket linkage in commits

- 🟡 Reference the ticket key in commit messages (e.g. `INSPR-189: phase 6 kernel + domain packs`). Match the repo's existing style (check `git log --oneline -10`).
- 🟡 Branch naming: include ticket key (e.g. `inspr-189-kernel-extraction`).
- 🟡 PR titles: ticket key + concise summary.

## Pattern: paimos CLI

The `paimos` CLI is the daily interface — prefer it over raw curl when possible. Standard invocation (after `paimos auth login` ran once at the host — see Auth above):

```bash
paimos <subcommand> [args]
```

No env-file sourcing needed; Keychain handles auth. If the host lacks a seeded Keychain (CI / headless / fresh-onboard), set `PAIMOS_API_KEY` in the environment as a fallback — but the canonical fleet pattern is Keychain-seeded.

Common subcommands (verify with `paimos --help` — re-survey before extending):
- `paimos issue get <KEY>` — read a ticket
- `paimos issue update <KEY> --status in-progress` — status transition
- `paimos issue list -p <PROJECT_KEY>` — list project issues
- `paimos issue comment <KEY> --body "..."` — add a comment
- `paimos auth whoami` — verify which instance + user the CLI is auth'd as

🟡 Re-survey existing tooling on `--help` before scoping any "extend X" ticket — the CLI may already cover the feature.

## Status states

`new` → `in-progress` (timer running) → `review` (PR pending) → `done` (acceptance met).
`blocked` while waiting on external dep — note the blocker. `wontfix` for closed-without-resolution; explain in note.

## Cross-cutting: licensing

- 🟡 Paimos itself is **AGPL-3**. For reusable modules, prefer **MIT-style permissive**.

---

*See also*: `/secrets` (`PPMAPIKEY.env` handling), `/dev` (ticket-key conventions in commits), `/ops` (FleetCom is a separate API). Full source: `AGENTS-CORE.md` and PROFILE-MARKUS topic `workflow/ppm`, plus `process/licensing`.*
