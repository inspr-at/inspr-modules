---
name: housekeeping
description: Repo + PPM hygiene sweep, then full codesweep for antipatterns, dead code, perf sinks, security/reliability issues, and extreme complexity or critical test gaps. Audits and prunes worktrees and stale local/remote branches, normalizes done-ticket acceptance and release metadata in PPM, challenges findings with the other agent’s strongest high-reasoning model, turns survivors into PPM tickets, triages backlog + Knowledgebase, then emits a TL;DR-ELI10 report and suggests /ship-next. Use for housekeeping, codesweep, full audit, tech-debt sweep, branch cleanup, or repo hygiene.
---

# Housekeeping

Run all 6 phases in order. High-signal findings only. Never modify code; phase 1 may only remove verified-merged/superseded refs and fix PPM metadata.

## 1. Repo & PPM hygiene
Audit first, remove only what is verified, keep anything ambiguous.

Audit:
- `git fetch --prune`, then list worktrees (`git worktree list`), local branches, and remote branches.
- Flag ambiguous history on long-lived stack/integration branches for review — never for deletion.

Remove (verified only):
- Merged: proven via `git branch --merged`, `git cherry`, or a merged PR (`gh pr list --state merged --head <branch>`) — squash merges do not show in `--merged`.
- Superseded: only with explicit evidence (e.g. closed PR pointing to its replacement); otherwise treat as ambiguous.
- Never touch the default branch, the current branch, or anything with uncommitted/unpushed work.
- Record each removed ref's sha before deleting (recovery trail). Local: `git branch -d` (`-D` only for verified squash-merges). Remote: `git push origin --delete`. Worktrees: `git worktree remove`, then `git worktree prune`.

PPM (paimos cli):
- Validate latest Done tickets: acceptance filled in, release metadata (fix version, release link) correct.
- Normalize where wrong; prefer update over duplicate.

Verify end state: refs pruned (`git remote prune origin`, `git worktree prune`), GitHub branch list matches local, releases and PPM consistent. Carry removed + kept-as-ambiguous lists into the report.

## 2. Codesweep
Scan the whole tree (respect ignores). Look for:
- Antipatterns
- Dead code
- Perf sinks
- Security & reliability (vulns, bad error handling, leaks, races)
- Extreme complexity or missing tests on critical paths

Each finding needs: id, category, severity, location, evidence, impact, suggested-fix.

## 3. Challenge
Detect which agent you are and call the other with its strongest high-reasoning model available:

- If you are Claude → call Codex (`codex`) with its best high / max reasoning model.
- If you are Codex → call Claude (`claude`) with its best xhigh / max reasoning model.

Prompt for the challenger (same in both directions):
```
Adversarial review. Reply only: KEEP | DOWNGRADE | DISCARD
then one short paragraph + refined fix if KEEP.
```

Keep only KEEP results. Discard aggressively. If the preferred model is unavailable, fall back to the next-strongest high-reasoning option on that side. Stop if no model is available and ask user how to proceed.

## 4. PPM tickets
Turn survivors into PPM tickets (using paimos cli).
Title: `[housekeeping] <imperative>`
Include evidence, challenger verdict, location. Tag with category + severity. Prefer update over duplicate.

## 5. Triage
Review full backlog + Knowledgebase. Close/merge obsolete items, re-rank, link new tickets, add KB entries for recurring patterns.

## 6. Report
```
## Overall (ELI10)
One short paragraph.

## Hygiene
Removed (with shas) and kept-as-ambiguous — one line each. PPM metadata fixes.

## Per-ticket (ELI10)
- TICKET-xxx — one-liner + severity

## Next
Suggest /ship-next on the highest-priority item.
Important note: Do not auto-implement the /ship-next as part of housekeeping, only suggest!
```
