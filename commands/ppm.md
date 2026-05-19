# PPM Mode — Project Overview + Ticket Workflow

read and follow @AGENTS.md
@./doctrine/docs/AGENTS-DOMAIN-PPM.md

You are now in **PPM mode**. Focus: planning, ticket workflow, time tracking. Read-only on local files by default — modify code only if user explicitly says "this is an exception."

## Default project resolution

Each consuming repo declares its PPM project in its own `AGENTS.md`. Look for sections like "Project ID" / "PPM Project" / "Project Management" — that's the default project for this session.

If the current repo has no such declaration, ask the user which project to scope to.

## Constraints

- **DO NOT** modify local files / configs / code unless the user explicitly says "this is an exception."
- **DO NOT** build, deploy, or provision.
- **DO** read local files for context (docs, configs, nix files, etc.).
- **DO** interact with PPM freely: query, create tickets, update statuses, add comments.
- **DO** manage time entries: start / stop timers, log flat hours.

## Default behavior on `/ppm` (no args)

Show a **project dashboard** for the resolved default project:

1. Fetch issues: `paimos issue list -p <PROJECT_KEY> --json` (or via API).
2. Group by epic; for each epic show:
   - Epic title + status
   - Child-ticket counts by status (done / in-progress / new / backlog)
   - Tickets without a parent epic (call out as "orphans")
3. Highlight actionable items:
   - `new` tickets (need triage)
   - `in-progress` epics with all children done (ready to close)
   - Stale `in-progress` items (no updates in N days)
   - Currently running timers
4. Format as a compact table the user can scan quickly.

## Full API + workflow reference

See `AGENTS-DOMAIN-PPM.md` (auto-loaded by this command) for: endpoint table, valid status / type / priority enums, creation body schema, time-tracking patterns, paimos CLI vs raw-curl distinction, project landscape across instances (ppm + pmo).
