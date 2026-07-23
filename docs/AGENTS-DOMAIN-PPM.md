# AGENTS — Domain: PPM

*Layer: `domain:ppm` · INSPR-189 Phase 6 · Loaded on demand by `/ppm`.*

Detailed rules for Paimos/PPM ticket work: `paimos` CLI, ticket conventions, project landscape, API endpoints, time tracking, status states. Kernel covers secret-handling side ("source the env, never cat"). This pack adds workflow depth.

**Load before**: any ticket work — create/update/query, time-tracking, ticket-aware automation. Pair with `/dev` when commits/PRs reference tickets.

---

## Auth

Two auth surfaces — DON'T conflate them:

**1. `paimos` CLI** — uses macOS Keychain (entry `paimos-cli/<instance>`) on macOS, Secret Service / KWallet on Linux, Credential Manager on Windows. INSPR workstation policy is interactive bootstrap: seed it once via `paimos auth login` at the keyboard and verify with `paimos auth whoami`. INSPR does not declaratively provision keyring credentials. Although the current CLI still exposes a scripted `--api-key` login path, do not use it; PAI-685 tracks its removal. For headless / CI, inject credentials only into the running process from approved encrypted storage (for example agenix). Never put them in command arguments, plaintext YAML, a repository, the Nix store, activation output, or logs.

- 🟡 **Onboarding new macOS host**: run `paimos auth login` interactively at the iMac/Mac keyboard (not over SSH — Keychain access is unreliable from non-GUI sessions). Enter the API key through the hidden prompt from the approved credential source; do not place it in command arguments or shell history:
  ```bash
  paimos auth login --url https://pm.barta.cm --name ppm
  ```
- 🟡 After `paimos auth login`, daily invocation is just `paimos <subcommand>` — no env-file sourcing needed; the OS keyring is authoritative whenever the headless runtime override is unset.
- 🟡 `paimos auth whoami` is the canonical auth smoke. To verify or migrate the workstation keyring specifically, unset all auth overrides for the command: `env -u PAIMOS_URL -u PAIMOS_API_KEY -u PPM_URL -u PPMAPIKEY paimos auth whoami`. inspr-doctor does this (INSPR-193, INSPR-225).
- 🔴 Sourcing `PPMAPIKEY.env` **alone** does not authenticate the `paimos` CLI. Current Paimos accepts the legacy pair `PPM_URL` + `PPMAPIKEY` for an environment-only session, but INSPR does not use that pair for workstation bootstrap. The preferred headless pair is `PAIMOS_URL` + `PAIMOS_API_KEY`; with a configured instance, `PAIMOS_API_KEY` alone overrides its keyring credential for that process. Never export either credential globally.

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

Run this diagnostic chain top-to-bottom — first thing that fails points at the fix. The env-file listing is relevant only to the separate raw-curl path:

```bash
env -u PAIMOS_URL -u PAIMOS_API_KEY -u PPM_URL -u PPMAPIKEY paimos auth whoami
                                    # is the OS keyring seeded? (prints user on success)
paimos doctor                       # full health report
~/Code/inspr/scripts/inspr-doctor.sh --verbose   # canonical fleet-wide onboarding check
ls ~/.inspr/secrets/agents/         # raw-curl env-files only; never read contents
```

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `PPMAPIKEY.env` missing | raw-curl secret not materialized on this host | this does not affect `paimos`; repair `inspr.secrets.agents` only if raw curl is required |
| `paimos auth whoami` exits 1 | OS keyring not seeded | run the `paimos auth login` block above **at the keyboard**, not over SSH |
| `paimos auth whoami` exits 1 after key rotation | stale OS-keyring entry | re-run `paimos auth login` with the fresh key |
| `$PPMAPIKEY` empty after sourcing | wrong filename / variable | `PPMAPIKEY.env` exports `PPMAPIKEY` (env-file convention = filename-as-varname) |
| `curl` returns 401 | wrong header / stale key | `Authorization: Bearer $PPMAPIKEY` (not `Token`); confirm key not rotated |
| Headless / CI | no usable interactive keyring | inject `PAIMOS_URL` + `PAIMOS_API_KEY` for that process only from approved encrypted storage; never render the credential to plaintext config or use it to bootstrap a workstation |

🔴 Never `cat`/`Read`/`head`/`tail` the .env files — `ls -la` only.

## Endpoints

- **One instance: PPM — `https://pm.barta.cm`.** Everything routes there; there is no second instance and no routing decision to make.
- Auth: `Authorization: Bearer $PPMAPIKEY` for raw curl; the `paimos` CLI uses a complete environment-only URL/key pair when present, otherwise configured routing plus a process-only `PAIMOS_API_KEY` override or the OS keyring.

🟡 The **PMO** instance (`pm.bytepoets.com`, the former second Paimos) was **decommissioned in June 2026** with the employer exit. Its keys (`PMOAPIKEY`, `PMOURL`, `PMOSERVER*`) and the `pmo` entry in `~/.paimos/config.yaml` are gone. If you see `$PMOURL`, `paimos --instance pmo`, or a former-work → PMO routing rule anywhere, it's stale — it will 401. Flag it.

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

🟡 **`DSC26` is personal, despite the `-26` suffix.** It's DSC Infrastructure (the `dsccfg` fleet). The suffix pattern-matched the legacy `BON26`/`MER26`-era keys, and doctrine mislabeled it as PMO-internal until 2026-07-13. It's an ordinary PPM project.

🟡 **`AMTWEB` is not `AMTCO`.** AMTWEB = the augmentoring.com website relaunch (`amt-com` repo). AMTCO = Augmentoring content production. Keys sit one character apart and `paimos` accepts either interchangeably.

## Default behavior

- 🟡 Treat Paimos APIs as **read-only by default**. Stay at project-level for unfamiliar projects.

## Workflow: backing tickets

- 🟡 Before starting work, check PPM for a backing ticket. If none exists and PPM writes are explicitly authorized, dedupe and create one; otherwise report the missing backing ticket and ask before writing.
- 🟡 Do NOT create local backlog files (no `BACKLOG.md`, no `TODO.md`). Backlog management is in PPM.
- 🟡 When PPM writes are explicitly authorized, update ticket status as work progresses: `new → backlog → in-progress → qa → done`.
- 🔴 Mark PPM tickets as `done` only when acceptance criteria are met. "Done means done."
- 🟡 Always reference tickets by human-visible key (e.g. `FLEET-79`) in chat, commits, branches, PR titles.

## Workflow: time tracking

- 🟡 When PPM writes are explicitly authorized, list running timers before starting one. If a timer is **obviously stale**—for example its ticket is terminal, its recorded session clearly ended, or later work superseded it—stop it first. Use the last defensible activity timestamp, annotate the cleanup, and never book unattended idle wall-clock as work. Leave plausibly active timers alone when the evidence is ambiguous.
- 🟡 When PPM writes are explicitly authorized, start the timer when beginning work and stop it when done. `mba` is `user_id 2`.
- 🟡 When PPM writes are explicitly authorized and work is done, update the ticket status AND stop the timer.

## Workflow: dedupe before creating

- 🟡 Before creating a PPM issue, search to dedupe via `GET /api/search?q=<topic>`.

## Workflow: GET-before-PUT

🟡 When a PPM write is explicitly authorized, GET before PUT. PPM PUT replaces the record **wholesale**. PATCH is silently ignored (no error, no effect).

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

🟡 **Type-value gotcha**: stored values and API responses use underscores
(`external_system`, `related_project`). URL path segments, `?type=` filters,
and `paimos knowledge` CLI positional values use canonical kebab-singular names
(`external-system`, `related-project`). JSON write bodies accept either form;
prefer the stored underscore form there. Verify `url_segment` mappings against
`GET /api/schema` when the server version changes.

### Endpoints (project-scoped)

| Operation | Endpoint |
| --- | --- |
| List (optionally filter) | `GET /api/projects/<id>/knowledge[?type=<url-type>]` |
| Create | `POST /api/projects/<id>/knowledge` (body: `KnowledgeEntryInput`) |
| Fetch one | `GET /api/projects/<id>/knowledge/<url-type>/<slug>` |
| Replace (rename via `body.slug`) | `PUT /api/projects/<id>/knowledge/<url-type>/<slug>` |
| Soft-delete (Trash) | `DELETE /api/projects/<id>/knowledge/<url-type>/<slug>` |

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

No env-file sourcing is needed on an onboarded workstation; the keyring handles auth. A fresh workstation must be bootstrapped interactively. For CI/headless use, inject `PAIMOS_URL` + `PAIMOS_API_KEY` into that process from approved encrypted storage; with configured routing, a process-only `PAIMOS_API_KEY` override is also supported. Do not use runtime injection to bootstrap a workstation.

Common subcommands (verify with `paimos --help` — re-survey before extending):
- `paimos issue get <KEY>` — read a ticket
- `paimos issue update <KEY> --status in-progress` — status transition
- `paimos issue list -p <PROJECT_KEY>` — list project issues
- `paimos issue comment <KEY> --body "..."` — add a comment
- `paimos auth whoami` — verify which instance + user the CLI is auth'd as

🟡 Re-survey existing tooling on `--help` before scoping any "extend X" ticket — the CLI may already cover the feature.

## Status states

Primary delivery path:

`new` (untriaged) → `backlog` (triaged) → `in-progress` (timer running) → `qa` → `done` (acceptance met).

Post-delivery states are `delivered` → `accepted` → `invoiced`. Use `cancelled`
for closed-without-delivery and explain why in the notes. The live schema has no
`review`, `blocked`, or `wontfix` state; record blockers in notes while keeping
the nearest truthful lifecycle state. Re-check `paimos schema --json` when the
server version changes.

## Cross-cutting: licensing

- 🟡 INSPR-owned public software and reusable modules use
  **AGPL-3.0-only**. A different license requires an explicit, documented
  decision; third-party components retain their upstream terms.

---

*See also*: `/secrets` (`PPMAPIKEY.env` handling), `/dev` (ticket-key conventions in commits), `/ops` (FleetCom is a separate API). Full source: `AGENTS-CORE.md` and PROFILE-MARKUS topic `workflow/ppm`, plus `process/licensing`.*
