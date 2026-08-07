---
name: tidyrepo
description: Cheap state-only hygiene sweep — worktrees, merged branches, PPM done-ticket metadata, backlog dedupe, KB freshness — then a short report. No code analysis, no cross-model challenge. Use after a release train or at the end of a working session. For a full tech-debt audit use /housekeeping instead.
---

# tidyrepo

State hygiene only. You are tidying the *situation around* the code, never the code itself.

## Hard boundaries

- **No codesweep.** No antipattern hunting, dead-code analysis, perf review, or complexity scoring. That is `/housekeeping`.
- **No cross-model challenge round.**
- **Cross-repo writes follow the authoring doctrine** (kernel): you may delete only branches *this agent lineage created* in a foreign repo. Anyone else's branch, and any other foreign-repo change, is a ticket — never a `git push --delete`.
- **Never delete an unmerged branch.** Never close a ticket.

## Steps

1. **Worktrees** — `git worktree list` in each repo in scope; prune ones that are gone or unchanged. Report the rest.

2. **Branches** — for each repo, classify every local and remote branch as merged / unmerged / unknown.

   > **Use the forge, not `merge-base`.** `git merge-base --is-ancestor <branch> origin/main` reports **squash-merged branches as unmerged** — squashing writes a new commit, so the branch tip is never an ancestor of main. Ask instead:
   > `gh pr list --head "$b" --state all --json number,state,mergedAt`.
   > Measured on nixcfg 2026-08-07: **32 of 45** remote branches had merged PRs that the ancestor check called unmerged.

   No PR found, or the forge is unreachable → **unknown**, not unmerged. Delete only: merged **and** created by this agent lineage. Everything else → one ticket in the owning project, grouped, with the classification in the body.

3. **PPM done-ticket normalization** — recently-closed tickets with empty acceptance criteria, missing close notes, or absent release metadata. Fill what is derivable from the merge/release; list what is not.

4. **Backlog triage** — surface duplicates and tickets overtaken by shipped work (say which release superseded them). Propose; do not close.

5. **Knowledgebase freshness** — is the session-pickup runbook current with the last release? Are doc-sync follow-ups piling up? Do guidelines still describe how deploys actually work?

6. **File a ticket only if something is obvious AND untracked.** Check the backlog first — re-filing what an existing ticket already covers is the opposite of tidying.

7. **Report** — short, plain, in this order: what was cleaned, what needs a human, what was deliberately left alone and why. Then suggest `/ship-next` if the backlog has an obvious next item.

## Scope

Default: the current repo. If the session touched sibling repos (a release-pin bump under the doctrine carve-out), include those for **own-residue cleanup only**.
