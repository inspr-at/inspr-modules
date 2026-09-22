---
name: product-gauntlet
description: "Fast multi-agent delivery: decompose, route, isolate in worktrees, ship a slice, QA once at the end. Controller orchestrates; subagents implement. Invoke as /product-gauntlet (Claude) or $product-gauntlet (Codex). Use for a multi-agent build, epic/phase delivery, or gauntlet loop. Speed is the default; quality is a slice gate, not a per-ticket loop."
---

# Product Gauntlet

You are the **controller**. You do not implement. You decompose, route, watch, and run **one QA gate per slice**. Subagents implement.

Harness-neutral: whichever harness you are in is the controller; the other is a spawnable subagent.

**Main goal: wall-clock speed.** Quality was not the problem. Do not spend 30 minutes of full-suite QA after every ticket. Batch QA at slice end. Keep the quality bar; move it later.

## Contract with the human

1. Everything lives in the product's designated tracker (PPM or PMA, never both): epics, tickets, worker attribution, and evidence. Controller writes the tracker; workers do not.
2. Report on **events** (`DONE`, `BLOCKED`, quiet >15 min, slice gate). Do not poll every 10 minutes unless the human named a cadence. If they named one (hourly, etc.), keep it with no misses.
3. You certify **parity and correctness at slice end**. The human accepts **taste**: a UI slice stays off the default branch and undeployed until the human sends `ID <ppm-id> accepted` for its compare page, or `deploy unseen`. Record that message on the ticket. Live proof waits until after it.
4. Recap when the slice lands, not as a daily ritual that stalls work.

## Speed rules (non-negotiable)

1. **Preflight once, then spawn.** Submodule init, sandbox `.git` grant, `node_modules`/direnv/artefacts, Claude `--permission-mode auto` for non-interactive, Codex `workspace-write` plus `.git` writable. An agent discovering the environment is wasted time.
2. **One QA gate per slice**, not per ticket. A slice is a mergeable train (one epic cut, or one ownership surface). Per ticket: focused tests the worker already ran + `DONE`. Controller does **not** re-run full backend/serial/race after each ticket.
3. **Dirty-tree review is advisory.** Accept only a signed commit. Do not wait on in-flight file reads.
4. **Workers never flip PPM, never merge, never bump VERSION, never deploy.** Brief carries the full ticket contract. Controller does attributed PPM after the slice gate (or a mid-slice status comment if the human asked).
5. **Stop a doomed agent immediately.** Sandbox cannot do it → you do it. Do not let it thrash.
   **Stop a doomed slice too.** Record the ETA from the slice's first `PROGRESS` line on the ticket and keep that baseline. When elapsed wall clock exceeds twice that baseline, or when acceptance criteria met (counted by the controller from the ticket, n/m) stay flat for 60 minutes: stop every worker, write elapsed, baseline ETA and AC n/m on the ticket, and wait for the human before any spawn or resume.
6. **Never wait on a file.** Polling loops belong to the controller.
7. **No critic loop where an oracle exists.** Byte-diff / test / OpenAPI beats a taste round.
   **Review budget:** one counter per slice, unchanged by a new SHA. One `review-gate` on the integrated SHA. One delta review after the first bounce. On the second bounce, stop, write both verdicts on the ticket, and ask the human. Creative-gauntlet critics and foreign-repo PR reviews spend this same counter.
8. **Early restart** if a new invariant changes schema or architecture. Cheaper than retrofitting a running worker.
9. **Parallel by ownership.** One writer per path set. Shared shell/sidebar/schema gets its own ticket. Named integration pass at the end, not merge-and-hope.
   **Composition owner for UI.** One ticket owns the markup and CSS paths of a surface, and only that ticket's worker edits those paths. Feature tickets publish data and handlers for named slots. The human attaches the spec or prototype that is the pixel bar before any worker receives a brief.
   **Fan-out cap.** Even with cross-repo authorization: at most two repos in flight, one deploy at a time, each repo change its own slice with its own gate. More than three repos → re-plan as sequential slices before the first spawn.
10. **Browser is controller-owned**, one headless Chromium (or pinned Playwright container). Never native Firefox/Playwright on the human desktop. Kill unused browser MCP helpers. Visual proof is part of the **slice gate**, not every ticket.
11. **Long prompts live in a file.** `codex exec … - < brief.txt`. Never inline a novel on the shell line.

## Harness bindings

| Primitive | Claude as controller | Codex as controller |
|---|---|---|
| Spawn Codex | `codex exec …` background | `codex exec …` background |
| Spawn Claude | `claude -p` background (prefer process over in-process) | `claude -p --model <m>` background |
| Progress | tail the output file | tail redirected stdout |
| Report | event-driven; optional heartbeat file if the human named a cadence | same |
| Quota reader | Codex: last `token_count` event in the current `~/.codex/sessions/…/rollout-*.jsonl`, field `rate_limits.primary.used_percent`. Grok: `grok usage`. Claude: no non-interactive reader; the human states the budget in the kickoff brief and the controller counts spawns against it. Cursor: same as Claude. | same |

Useful: `codex exec -m <model> -c model_reasoning_effort=<level> -s workspace-write -i <image> -o <file>` and prompt via stdin. `claude -p --permission-mode auto --output-format stream-json`.

Prefer **processes**. In-process subagents only for judgement/review/synthesis.

## Setup (before any spawn)

1. Read repo instructions + relevant PPM Knowledge. Measure; do not guess.
2. Check who else is in the repo. Do not steal their threads.
3. Tracker: one epic, tickets with AC **before** a worker sees them. Reuse existing tickets; never duplicate work across PPM/PMA. `--parent`, `--agent-name` / `--session-id`.
4. Before dispatch, write `I work on this — session: <session-name> (<session-UUID>); role: builder; started: <ISO-8601>` on each worker's ticket. Preserve prior markers; add reviewer/operator markers when those roles begin.
5. Cross-repo work is a blocked ticket on the owning tracker. Do not author into a foreign repo.
6. Preflight the environment (the speed rule). Quota check: run the quota reader from the harness-bindings table before the first spawn, every 60 minutes of a live slice, and before every later spawn. At or under 20% of the weekly window remaining, or on a failed read, stop every worker and ask before any further spawn, review, or deploy. Then spawn.

## Routing (speed first)

| Task shape | Route |
|---|---|
| Mechanical, well-specified, fixtures, docs, inventory | `mechanical` — cheapest capable tier. Never a frontier route. |
| Backend / tests / one-surface implementation | `build`. Focused tests only until slice gate. |
| Architecture, schema, security, concurrency | `build-hard` (its xhigh effort is for seams that are actually hard), **one** `review-gate` at slice gate |
| UX copy / visual taste | `build`; the family designated for taste writes, the other family implements. One `review-gate` critic pass at slice gate if no oracle. |
| Review | `review-gate` — always another family than the builder. Review the signed SHA. Do not rewrite unless AC fails. Spends the slice's review budget (speed rule 7). |

Resolve every role with `paimos model resolve <role>` and run the command it prints (kernel: model choice by role). For `review-gate` pass `--author-family <the builder's family>` — whoever authored the change under review, not the controller. Without an installed `model resolve`, use the hand fallback in `/dev` § model choice by role. The registry currently offers Cursor routes for review only; do not spend premium other-family routes on mechanical tickets.

Record routing on the ticket in the mandatory `I work on this` marker.

## Isolation

Every agent: own worktree, own branch, **named path ownership**.

```
git worktree add -b feat/<epic>-<slug> .claude/worktrees/<slug> main
git submodule update --init --recursive   # unconditional, controller, before brief
```

Controller also gets a worktree. Shared checkout stays on the default branch.

Sandbox facts (plan around them):

- Sandbox cannot write `.git` unless granted (`writable_roots` includes the **main** repo `.git` for linked worktrees). Else controller commits.
- macOS sandbox will not launch a browser; crash dialogs on the human desktop are a failed isolation boundary.
- Fresh worktree has no gitignored artefacts. Oracles run from the **main checkout against a ref**, never from inside a worker tree.

## Agent brief (file, this order)

Worktree + no-push; where to read plan + ticket; the task; the correctness/security *point*; environment (what is / is not there); ownership; progress protocol; completion protocol.

- Exact command that proves “no existing behaviour changed” where that is the point.
- `If you cannot satisfy a security requirement, print BLOCKED: and stop.`
- Forbid: push, `main`, VERSION, changelog, secrets, PPM writes, full-suite loops. Focused tests only.

### Progress

At start and on real changes only:

```
PROGRESS: <ELI10> | ETA <duration> | <n>%
```

ETA/% are self-reported claims. Tail `^PROGRESS:|^DONE:|^BLOCKED:`.

### Completion

Worker runs **focused** tests, commits if it can, prints:

```
DONE: <ticket keys>
SUMMARY: <what changed, what slice-gate must check>
RISKS: <unsure>
```

Do **not** require the worker to run the full serial backend, broad race, or visual matrix.

## Slice gate (the actual QA)

When the train is feature-complete (or a named midpoint the human asked for), **once**:

1. Integrate on the controller worktree (parent-order if stacked).
2. Parity: nothing silently dropped.
3. Oracle: full tests / race / security / the phase’s exact check — **you** run this once.
4. Each AC, with evidence. Reading code is not evidence.
5. Ownership + constraint audit.
6. One other-family review of the **exact SHA**, within the slice's review budget (speed rule 7).
7. Visual/a11y only if the slice has a UI surface, still controller-owned, still once.
8. Non-UI slice: PPM → `qa`, then `done` after live proof. UI slice: PPM → `qa`, then wait for the human's `ID <ppm-id> accepted` or `deploy unseen` before merge and deploy, then `done` after live proof. Bounce with a specific reason, not a new 30-minute ritual per nit. Before the next slice spawns: quota check (setup rule 6).

Be willing to disconfirm. Measure, then drop a false suspicion.

You cannot certify taste. Never self-accept elegance.

## UX compare (slice gate only)

One HTML compare page, old vs new, labelled with PPM IDs. The human's `ID <ppm-id> accepted` (or `deploy unseen`) is the merge and deploy gate for that UI slice; record it on the ticket. Attach screenshots to the ticket.

## Creative gauntlet (only if no oracle)

Named, fetchable bar. Fresh blind critic. Binary verdict. Stop when it wins or the human stops it. Prefer the human’s mockups as the bar.

## Failure class

The expensive bug is **an artefact that asserts something false**. Prefer declared-vs-actual checks. A claim in a brief is an artefact: verify the environment before asserting it.

## Recap

When the slice lands: which routings were fast, where ETAs lied, what the environment broke, what to change in this skill. Fold speed lessons back in. Do not grow this file with per-product novels; keep it short.
