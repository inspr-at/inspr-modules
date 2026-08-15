# PPM Mode — Project Overview + Ticket Workflow

read and follow @AGENTS.md
@./doctrine/docs/AGENTS-DOMAIN-PPM.md

You are now in **PPM mode**. Focus: planning, ticket workflow, time tracking. Read-only on local files by default — modify code only if user explicitly says "this is an exception."

## Default project resolution

Each consuming repo declares its Paimos project in its own `AGENTS.md`. Look for sections like "Project ID" / "PPM Project" / "Project Management" — that's the default project for this session.

If the current repo has no such declaration, ask the user which project to scope to.

🔴 **Resolve the INSTANCE, not just the project key.** The CLI defaults to
`ppm` (personal). A business repo whose project lives on `pma` will, unqualified,
silently read the wrong tracker — in an augmentoring-team repo that means hitting
a *frozen* project instead of the live one. Read the instance from the same
`AGENTS.md` declaration and pass it explicitly on every call:

```bash
paimos --instance <declared> issue list -p <PROJECT_KEY>
```

If the repo names a project but not an instance, that is a defect in the repo's
`AGENTS.md` — say so rather than guessing. Personal and INSPR work is `ppm`;
business/augmentoring work is `pma`.

🟡 **A key that does not resolve is not proof the data is gone.** Frozen
projects are omitted from `project list` and rejected by project-scoped calls,
while their issues stay readable by key. Verified 2026-08-15 on `ppm`:

| Operation | Result |
|---|---|
| `paimos project list` | frozen projects **absent** |
| `paimos issue list -p AMTWEB` | `Error: project key "AMTWEB" not found (are you on the right --instance?)` |
| `paimos issue get AMTWEB-1` | **works** — returns the ticket |

That error text is actively misleading: it blames `--instance` when the instance
is correct and the project is merely frozen. An agent followed exactly that hint
against `AGM`, concluded the backlog was lost, and recreated four tickets from
reconstructed evidence — the originals were readable the whole time. **Before
concluding anything is missing, try `issue get <KEY>`.**

## Constraints

- **DO NOT** modify local files / configs / code unless the user explicitly says "this is an exception."
- **DO NOT** build, deploy, or provision.
- **DO** read local files for context (docs, configs, nix files, etc.).
- **DO** query PPM freely.
- **DO NOT** create or mutate tickets, comments, statuses, or time entries unless
  the user explicitly authorized project-management changes. Invoking `/ppm`
  alone is read-only and does not grant write authority.

## Default behavior on `/ppm` (no args)

Show a **project dashboard** for the resolved default project:

1. Fetch issues: `paimos --instance <declared> issue list -p <PROJECT_KEY> --json` (or via API).
2. Group by epic; for each epic show:
   - Epic title + status
   - Child-ticket counts by status (new / backlog / in-progress / qa / done /
     delivered / accepted / invoiced / cancelled)
   - Tickets without a parent epic (call out as "orphans")
3. Highlight actionable items:
   - `new` tickets (need triage)
   - `in-progress` epics with all children done (ready to close)
   - Stale `in-progress` items (no updates in N days)
   - Currently running timers
4. Format as a compact table the user can scan quickly.

## Full API + workflow reference

See `AGENTS-DOMAIN-PPM.md` (auto-loaded by this command) for: endpoint table,
valid status / type / priority enums, creation body schema, time-tracking
patterns, paimos CLI vs raw-curl distinction, and the project landscape on the
single PPM instance.
