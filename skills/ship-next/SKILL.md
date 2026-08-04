---
name: ship-next
description: "Propose and deliver the single right next software change end-to-end: implement, validate, commit, push, merge, deploy, verify live, document, and clean up. Use when the user invokes $ship-next in Codex or /ship-next in Claude Code, asks what should ship next, requests the next delivery item, or replies with a bare 'go' to a clearly formatted Ship Next proposal in the current thread."
---

# Ship Next

Run a two-phase delivery loop: propose exactly one item, then wait for `go` before shipping that exact item completely.

## Interpret the invocation

- Enter **proposal mode** when asked what to do next or when invoked without an unambiguous approved proposal.
- Enter **execution mode** only when the user says `go` in response to the most recent Ship Next proposal, or explicitly invokes this skill with `go` while that proposal remains clear in the current thread.
- Bind `go` only to that proposal. Do not treat it as standing permission for later items or broader scope.
- If the proposal is missing, ambiguous, contradicted by newer instructions, or materially stale, stop and ask for clarification or issue a fresh proposal.

## Proposal mode

1. Read applicable repository instructions, doctrine, tracker state, current code, CI, release, deployment, and live evidence.
2. Select one smallest valuable, unblocked delivery item. Rank candidates in this order:
   - live regression, security failure, broken required check, or production risk;
   - incomplete release, deployment, migration, or parent closeout;
   - highest-impact unblocked product work;
   - documentation or cleanup only when it restores operational truth, safety, or delivery flow.
3. Prefer finishing an active outcome over opening unrelated work. Do not choose merely because an item is oldest or labeled highest priority.
4. Make only read-only checks in proposal mode. Do not start implementation or mutate trackers.
5. Propose exactly one item using this format:

```text
**TL;DR (ELI15):** <one very brief sentence describing what the user gains; use two only when truly necessary>

**Why next:** <one brief sentence explaining why this outranks the alternatives>

Say **“go”**.
```

Do not add a plan, implementation detail, candidate list, or extra question after this format. If no defensible next item exists, say the backlog is complete and do not ask for `go`.

## Execution mode

Treat `go` as authorization for the normal end-to-end delivery actions required by the accepted proposal: implementation, validation, commits, pushes, pull requests, merge when requirements pass, documented deployment, live verification, evidence updates, and cleanup.

Before changing state:

1. Revalidate the proposal against current local and remote state.
2. Read the repository's instructions and canonical operational doctrine.
3. Confirm the working tree and preserve all unrelated user changes.
4. Resolve the exact issue, branch, deployment target, required checks, and definition of live success.

Then continue autonomously through the entire delivery sequence:

1. Create or update the tracking item when the project's workflow requires it.
2. Use a focused branch. If using a temporary worktree, place it under the project's normal worktree area and remove it after merge.
3. Implement the smallest complete change without unrelated refactors.
4. Run targeted tests, then the repository's required validation and security gates.
5. Review the diff for correctness, scope, secrets, generated artifacts, and unintended changes.
6. Commit with a clear message and push the branch.
7. Open or update the pull request, observe required CI, address failures, and merge only when repository requirements are satisfied.
8. Release and deploy through the documented path. Bind deployment evidence to the exact commit, artifact, image, or digest.
9. Verify the deployed version and the actual user-visible or operational behavior. A health check alone is insufficient when the change has observable behavior.
10. Update tickets and canonical evidence truthfully, return the primary checkout to current main, remove temporary worktrees, and prune stale metadata.

Keep working through ordinary failures. Diagnose and repair them within scope instead of stopping after the first failed test or CI run.

## Completion and blockers

Do not call the item shipped and do not propose another item until implementation, required CI, merge, deployment, live behavior, evidence, and cleanup are complete.

If the project has no deployable surface, define the equivalent published or integrated terminal state in the proposal and verify that state after merge.

Stop and request the specific missing authority when completion requires:

- destructive or irreversible production/data operations not inherent in the accepted proposal;
- viewing, copying, rotating, or exposing secret values;
- human authentication, passkeys, CAPTCHA, or another attended action;
- bypassing branch protection, required review, policy, or safety controls;
- messaging people, spending money, or expanding into a materially different task.

`go` never overrides system policy, repository doctrine, or required human controls. When blocked, report the blocker and the exact action needed; do not distract with a new next-item proposal.

## Completion handoff

After live verification, report concisely:

```text
**Shipped:** <what is now complete and live>

**Look at:** <the exact URL, UI behavior, artifact, or operator-visible result to inspect>

**Evidence:** <commit/PR/release/deployment/live-check identifiers>

**TL;DR (ELI15):** <one very brief sentence describing the next gain>

**Why next:** <one brief sentence explaining why this outranks alternatives>

Say **“go”**.
```

If there is no defensible next item, replace the final proposal with a concise backlog-complete statement and do not ask for `go`.

## Invocation

- Codex: `$ship-next`
- Claude Code: `/ship-next`
- Either tool may invoke it implicitly from a matching request or a valid bare `go` continuation.
