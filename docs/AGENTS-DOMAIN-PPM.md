# AGENTS — Domain: PPM

*Layer: `domain:ppm` · INSPR-189 Phase 6 · Loaded on demand by `/ppm`.*

Detailed rules for Paimos/PPM ticket work: `paimos` CLI, ticket conventions, project landscape, API endpoints, time tracking, status states. Kernel covers secret-handling side ("source the env, never cat"). This pack adds workflow depth.

**Load before**: any ticket work — create/update/query, time-tracking, ticket-aware automation. Pair with `/dev` when commits/PRs reference tickets.

---

## Auth

- 🔴 Auth via `( set -a; source ~/.inspr/secrets/agents/PPMAPIKEY.env; cmd; set +a )` — exposes `$PPMAPIKEY` to the wrapped command only.
- 🔴 NEVER `cat`, `head`, `tail`, `Read`, or print the env file. Verify presence with `ls -la` only.
- 🔴 Never put secrets, API tokens, or credentials in ticket descriptions or notes; they stay in agenix.

See `/secrets` for full secret-handling pipeline.

## Endpoints

- Use `$PMOURL` for HTTP API calls.
- 🔴 NEVER use `$PMOSERVERURL` for HTTP — it returns 404. It's the SSH/server hostname for non-HTTP access.
- Two PPM instances:
  - **PPM**: `pm.barta.cm` — personal/INSPR projects
  - **PMO**: BYTEPOETS instance — separate auth, separate project namespace

Routing rule: in `~/Code/nixcfg`, `~/Code/inspr/`, etc. → PPM. In `~/Code/BYTEPOETS/` → PMO.

## Project key reference

Use the human-visible project key in chat, commits, branches, PR titles. Numeric DB id is for API calls only.

| Key         | Project                                     | Instance |
| ----------- | ------------------------------------------- | -------- |
| `INSPR`     | Umbrella initiative                         | PPM      |
| `NIX`       | nixcfg                                      | PPM      |
| `PAI`       | Paimos (the OSS PM tool itself)             | PPM      |
| `FLEET`     | FleetCom                                    | PPM      |
| `BON26`     | BYTEPOETS Bonelio 2026                      | PMO      |
| `MER26`     | BYTEPOETS Merlin 2026                       | PMO      |
| `DSC26`     | BYTEPOETS internal                          | PMO      |

🔴 BYTEPOETS project data (BON26, MER26, etc.) is **confidential client information**. Do not enumerate ticket details broadly without specific reason.

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

The `paimos` CLI is the daily interface — prefer it over raw curl when possible. Standard invocation:

```bash
( set -a; source ~/.inspr/secrets/agents/PPMAPIKEY.env; paimos <subcommand> [args]; set +a )
```

Common subcommands (verify with `paimos --help` — re-survey before extending):
- `paimos ticket get <KEY>` — read a ticket
- `paimos ticket update <KEY> --status in-progress` — status transition
- `paimos timer start <KEY>` / `paimos timer stop` — time tracking
- `paimos search <topic>` — dedupe before create

🟡 Re-survey existing tooling on `--help` before scoping any "extend X" ticket — the CLI may already cover the feature.

## Status states

`new` → `in-progress` (timer running) → `review` (PR pending) → `done` (acceptance met).
`blocked` while waiting on external dep — note the blocker. `wontfix` for closed-without-resolution; explain in note.

## Cross-cutting: licensing & framing

- 🟡 License posture for any module BYTEPOETS might adopt: prefer **MIT-style permissive over AGPL-3** (Paimos itself is AGPL-3).
- 🟡 Discuss Paimos/PMO/PPM publicly as Markus's personal OSS contribution — NOT as "BYTEPOETS's product". BYTEPOETS context is separately governed; do not reference it in public-facing INSPR copy without confirmation.

---

*See also*: `/secrets` (`PPMAPIKEY.env` handling), `/dev` (ticket-key conventions in commits), `/ops` (FleetCom is a separate API). Full source: `AGENTS-CORE.md` and PROFILE-MARKUS topic `workflow/ppm`, plus `process/licensing` and `style/communication` for BYTEPOETS framing.*
