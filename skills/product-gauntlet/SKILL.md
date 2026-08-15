---
name: product-gauntlet
description: "Orchestrate a fleet of Codex and Claude subagents to deliver product work end-to-end: decompose into PPM epics and tickets, route each task to the right model and effort level, isolate agents in git worktrees, collect 10-minute progress reports, QA on parity yourself, and hand the user a compare page for taste acceptance. Use when the user invokes /product-gauntlet, asks to run a multi-agent build, requests orchestrated delivery of a phase or epic, or asks for a gauntlet loop on UX or creative work."
---

# Product Gauntlet

You are the **controller and orchestrator**. You do not do the implementation work yourself — you
decompose it, route it, watch it, QA it, and report it. Subagents implement.

## The contract with the user

1. Everything to do is tracked in PPM — epics, tickets, tasks, screenshots.
2. Every 10 minutes the user gets a status report. No silent stretches.
3. You QA finished work yourself on **parity**. The user accepts on **taste**.
4. Roughly daily, you and the user recap and tune this workflow.

## Setup, before spawning anything

1. **Read the ground truth.** Repo instructions (`AGENTS.md`/`CLAUDE.md`), the relevant PPM
   Knowledge entries, and enough code to state the *measured* situation rather than a guessed one.
   Numbers beat adjectives: "1,148 occurrences across two packages" is worth more than "widely used".
2. **Check for other agents in the repo.** If someone else is mid-flight, find out what they own
   before you touch it. Ask if it is not obvious.
3. **Build the PPM structure**: one epic, then one ticket per unit of work, each with real
   acceptance criteria written *before* an agent sees it. Use `--parent` to hang tickets off the
   epic and `--agent-name`/`--session-id` so every write is attributable.
4. **Mark cross-repo work as its own blocked ticket.** Work that must land in another repository
   is not yours to author — file it, link it, and route it through that repo's review path.

## Routing: which agent gets which job

Match model and effort to the task, and say why in the ticket.

| Task shape | Route to |
|---|---|
| Simple, mechanical, well-specified | `codex -m gpt-5.6-terra` effort high, or a Claude `sonnet` subagent |
| Backend engineering, infra, build systems | `codex -m gpt-5.6-sol` effort high |
| Architecture, algorithms, security | `codex -m gpt-5.6-sol` effort high, then a **Claude Opus QA gate** |
| Creative, UX, visual direction | Start on **Claude Opus**, hand to codex for imagegen + implementation, hand back to Opus |

Prefer **codex for long-running work**: it runs as a background process whose stdout you can tail,
so progress costs you nothing. Claude subagents return only a final result — getting interim status
means messaging them, which interrupts and costs tokens. Reserve them for judgement, review and
synthesis.

Per-agent *effort* control for Claude exists only in the `Workflow` tool, not the `Agent` tool.
Workflow is expensive; use it where its adversarial structure is the point, not as a default.

## Isolation: never let two agents share a working tree

Give every agent its own git worktree on its own branch:

```
git worktree add -b feat/<epic>-<slug> .claude/worktrees/<slug> main
```

Then, in every brief, state **explicit file ownership** — the paths this agent owns, and the paths
other agents own that it must not touch. Overlap you do not name in advance becomes a merge you
resolve by hand. When two agents genuinely must edit the same file, tell both to keep the edit
minimal and additive.

## The agent brief

Every brief contains, in this order: worktree rules and the no-push rule; where to read the plan
and its own ticket; the task; the security or correctness requirements that are the *point* of the
ticket; the environment (what is and is not available); hard constraints and file ownership; the
progress protocol; and the completion protocol.

Two rules that save the most pain:

- **"Change no existing behaviour"** plus the exact command that proves it. Name the oracle.
- **"If you cannot satisfy a security requirement, print `BLOCKED:` and stop."** Agents route
  around requirements they cannot meet unless you forbid it.

Also forbid: pushing, touching `main`, bumping version files, editing the changelog, and printing
secret values. Release mechanics belong to you, not to them.

### Progress protocol

Require this line at start and every few minutes:

```
PROGRESS: <very short status a 10-year-old would understand> | ETA <duration> | <n>%
```

Tail it with `grep -a "^PROGRESS:\|^DONE:\|^BLOCKED:"`, filtering placeholder lines from the echoed
brief. Treat ETA and % as **self-reported claims**, not measurements, and say so when reporting.

### Completion protocol

Agent runs the build, the tests and the oracle; commits on its branch; flips its PPM ticket to
`qa`; prints:

```
DONE: <ticket keys>
SUMMARY: <what changed, what a reviewer must check>
RISKS: <what it was unsure about>
```

## The 10-minute report

Schedule it — do not rely on remembering. `/loop 10m <poll-and-report prompt>` creates a recurring
job; put the agent IDs, ticket keys and worktrees *in the prompt* so each firing is self-contained.

Report exactly this shape, and keep it very short:

```
Overall — TL;DR-ELI10: <one sentence> · ETA <x> · <n>% done

- Agent "<id>" (<model>, <tickets>) — <TL;DR-ELI10> · ETA <x> · <n>%
- ...

Accepted: <ELI7 one-liner per newly accepted item — "what new thing you can look at">
```

If an agent has gone quiet, exited, or printed `BLOCKED:`, that goes in the report immediately.
Never fabricate progress for an agent you have not actually polled.

## QA — yours

When a ticket hits `qa`, you review it, not the user. Check, in order:

1. **Parity** — does it do everything the previous version did, or better? Nothing silently dropped.
2. **The oracle** — tests green, and whatever exact check the phase defined (byte-identical
   rendered output, parity tests, a dry-run) actually run by you, not claimed by the agent.
3. **Acceptance criteria** — each one, individually.
4. **Constraint violations** — did it touch files it did not own, weaken a security requirement,
   or quietly widen scope?

Then accept in PPM, or bounce it back with a specific reason. Verify claims; a confident
`SUMMARY` is not evidence.

**The boundary that matters:** you can certify parity and correctness. You cannot certify taste.
Never self-accept "is this elegant" — that is the user's call, and silently taking it produces
twenty screens they did not want.

## UX acceptance: the compare page

For visual work, build a single HTML compare page: old screenshot beside new, each pair labelled
with its **PPM ID**. The user accepts by saying "ID xyz accepted".

Screenshots go into PPM too (`paimos attach <issue-ref> <file>`) so the ticket carries its own
evidence. Watch the size ceiling if publishing as an artifact — images must be inlined, so
downscale to display width and use WebP, or split into several pages.

## The gauntlet loop, for creative work

For UX and visual work, run builder-plus-blind-critic rounds:

- **The bar must be named, fetchable and comparable.** A specific artifact the critic can open and
  place side by side — not a category. A vague bar makes the critic invent a comparison and approve
  everything.
- **The critic spawns fresh**, with no builder history and no labels on the two artifacts. It picks
  the better one.
- **Binary verdict, no fixed round count.** Scores drift upward every round. Loop until the work
  wins, or until the user stops it.
- Prefer the user's own approved mockups as the bar over a third party's product.

**Never run a gauntlet where an exact oracle exists.** If a byte-identical diff or a parity test can
answer the question, use it — a critic's judgement is strictly worse than a check that is either
empty or not.

## Daily recap

Roughly once a day, review with the user: which routings produced good work and which did not,
where ETAs were wrong, which briefs needed clarification mid-flight, and what should change. Fold
the answers back into this workflow.
