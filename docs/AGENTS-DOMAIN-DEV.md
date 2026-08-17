# AGENTS — Domain: Dev

*Layer: `domain:dev` · INSPR-189 Phase 6 · Loaded on demand by `/dev`.*

Detailed rules for code work: git, build/test gates, style, refactor, gh CLI, just, scripts, editing discipline. Kernel (auto-loaded) covers destructive-git irreversibles and basic identity/style. This pack adds daily-workflow depth.

**Load before**: code editing, refactor, multi-commit work, PR work, test/lint gates. Pair with `/secrets` for credentials, `/nix` for nix code.

---

## Pattern: git workflow

### Identity (kernel + extras)

Identity comes from the private kernel; never invent placeholders. Extras:

- 🟡 Identity/dev config lives **declaratively** in nixcfg. `git config --global` or any fleet-wide imperative move requires confirmation.
- 🟡 Per-repo git config (no `--global`) on bootstrap; nixcfg is canonical for fleet-wide.
- 🟡 PAT identity: entity that makes decisions while no human is present → its own GitHub account; otherwise human's account is fine.

### Multi-org auth

- Use alias form `git@<alias>:<owner>/<repo>.git` for pushes; never bare `git@github.com:`. Personal: `git@git-personal:markus-barta/...`.
- Declare credential helpers via HM `programs.git.settings.credential`, not `gh auth setup-git` (collides with HM read-only config).
- Auto-generated `includeIf hasconfig:remote.*.url` rules MUST be paired HTTPS+SSH — `*` doesn't cross URL component boundaries. Prefer content-derived rules over gitdir lists.
- Migrating to HM-managed git config: **rename** legacy `~/.gitconfig` (don't delete) — silently shadows `~/.config/git/config`.

### Commit safety (extras beyond kernel)

Kernel: scan diff + status before every commit; never amend; never destructive ops. Extras:

- 🔴 On potential secret in diff: STOP → alert → suggest env var → wait for confirmation.
- 🟡 Re-`git add` edited files before commit, or use `git commit -a` for tracked files. `AM` letter combination warns of stale staged versions.
- 🟡 When commit appears to silently abort + push says "Everything up-to-date", check `git status` for `MM` state — pre-commit linter ate the staged diff.
- 🟡 Group into logical commits; don't lump unrelated changes. Use the repo's existing commit message style (`git log --oneline -10`). Branch changes require user consent.

### Push flow & `/push`-family

- Push is normal flow on agreed changes — do it without asking. After commits: `git pull --rebase && git push`.
- For big review: `git --no-pager diff --color=never`.
- Multi-agent repos with not-yours dirt: `git stash push -- <paths>` (path-scoped), pull/push/pop. Don't `git stash` everything.
- `/push`: commit and push current working directory repo only.
- On `/push`: STOP and alert if diff or working tree shows potential secrets or unexpected files before any push.

## Pattern: PR and gh CLI

- 🟡 Use `gh pr view/diff` for PRs — never paste GitHub URLs.
- 🟡 In PR replies cite fix and file/line. Resolve threads only after the fix lands.
- 🟡 On CI red: `gh run list/view`, rerun, fix, push, repeat to green.

## Pattern: Build / test / docs gates

- 🟡 Before handoff, run the full gate: lint, typecheck, tests, docs.
- 🟡 Use the repo's package manager and runtime; no swaps without approval.
- 🟡 Update docs (README/RUNBOOK) when behavior or API changes — no ship without docs.
- 🟡 After shipping anything claimed-as-done, do a structured C/H/M/O severity pass through the artifacts: "would this withstand a tough security and validity audit?".
- 🟡 A claimed-as-done change must name its durable, inspectable artifact evidence. For code, record the repository plus commit or commit range; for deployments, bind the exact release/image/digest to a live behavior check; for documents and generated assets, name the durable artifact/version. Status prose, timestamps, and “tests passed” without the resulting artifact are not a completion trail.

## Pattern: critical thinking & editing discipline

- 🔴 **Read before replacing.** Verify full context of edits.
- 🔴 **Clarity over speed.** Uncertain? Ask first — one question beats three bugs.
- 🟡 Verify post-action (`git status`, `ls -la`, decrypt-test); verification is part of the operation. Verify outputs **structurally** (size, content sniff), not just by exit code.
- 🟡 Fix root cause, not band-aid. Honor existing patterns. On conflicts, call them out and pick the safer path. When unsure, read more code; if still stuck, ask with a short option list.
- 🟡 Vendor advice = useful signal, not authoritative. Re-derive against own axes (portability, rotation, scope).
- 🟡 "Smaller=safer vs bigger=right": verify bigger option is feasible TODAY; defer for brittleness, not size.
- 🟡 Probe actual endpoint behavior before designing idempotency strategy on unfamiliar APIs.
- 🟡 Re-survey tooling with `--help` before scoping any "extend X" ticket.
- 🟡 Web research: search early; never invent URLs; quote exact errors. Source preference 2026+ → 2025+ → older.
- 🟢 Treat unrecognized changes as another agent's work; keep going on your scope; stop+ask only on issues.

## Pattern: refactor & script design

- 🟡 No repo-wide search/replace scripts. Keep edits small and reviewable.
- 🟡 Joining an existing repo with its own pattern: prefer **hybrid coexistence + a follow-up ticket** over unilateral refactor on prod code.
- 🟡 sed-renaming functions across a known set: ALWAYS use `comm(1)` over BOTH function-name lists to find the FULL collision set BEFORE writing the rename loop.
- 🔴 Every script touching a remote auth system defaults to **read-only/preserve**; require explicit opt-in for any state change.
- 🔴 Any script that prints secrets to stdout defaults to redacted (`<redacted, length=N>`); cleartext via opt-in only (`--print-secret`).
- 🟡 Auto-detect heuristics that depend on tool presence: normalize PATH BEFORE probing with `command -v`.
- 🟡 For self-hostable systems with non-obvious init traps, maintain ONE executable bootstrap as canonical state spec.

## Pattern: shell/just gotchas

- 🟡 Avoid English-contraction apostrophes (`don't`, `won't`) in awk/shell embedded in single-quoted strings — they prematurely terminate the quoted region.
- 🟡 In `just` recipe docstrings, show invocations with **positional args only** — never `name=value` syntax.

## Pattern: file & workspace conventions

- 🟡 Markus's repos live under `~/Code/`. If missing, ask to clone `https://github.com/markus-barta/<repo>.git`. Third-party/OSS clone under `~/Projects/3rdparty/`. Never use `~/Code/scratch/`.
- 🟡 Edit the `+agents/` directory only when user explicitly permits.
- 🟡 Use `paimos onboard --project INSPR` for current INSPR state. The local
  `inspr/playbook.md` is a historical field log, not the current source of truth.
- 🟡 For "use a screenshot": pick newest PNG in `~/Desktop` or `~/Downloads`, verify by content (ignore filename), size-check via `sips`, optimize via `imageoptim`. STOP if tool missing.
- 🟡 Use `rsync --checksum` reflexively for any file that "should have changed but didn't seem to".

## Pattern: markdown policy (kernel + extras)

Kernel: never create new `.md` files unless explicitly requested; prefer editing existing docs. Extras: when tempted, ask first **which existing doc to update**. "Document X" → update `README.md` or `RUNBOOK.md`. No markdown backlog files in nixcfg — backlog is in PPM.

## Pattern: naming conventions

- 🟡 In SSH pubkey comments and 1P entry titles, use the FULL local hostname + FULL local username (`user@host`), NOT chip codenames.
- 🟡 The `.cm` TLD is **intentional**, not a typo for `.com`. Kernel rule, repeated for emphasis: do not auto-correct.

## Pattern: long-running commands

- 🟡 Prefix commands >10s with `date &&` (bash) or `date; and` (fish) for timestamping. Applies to nix builds, docker ops, large file ops, test suites, package installs.
- 🟡 Background or zellij session for jobs >30s.
- 🟡 Terminal multiplexer is **zellij**, NOT tmux. Layouts in `~/.config/zellij/`. _(Was a kernel rule until the INSPR-189 budget audit; demoted here because it is a preference, not a turn-1 irreversible.)_

## Sync triad (Prime Directive)

🔴 **Keep config, docs, and tests in sync.** A change to one without the others is incomplete.

## Workflow: design doctrine & rollout

- 🟡 New credential primitive: first ask "human-owned or machine-owned identity?" — rules out half the options.
- 🟡 Prefer primitives that NEVER rotate (deploy keys, classic PATs) or auto-rotate invisibly (App tokens, OIDC). Manual rotation only where rotation is the point.
- 🟡 INSPR-primitive test: "does it survive substrate migration with config-level changes only".
- 🟡 Capture the pivot trail for any decision that reorientated multiple times — prevents re-litigation.
- 🟡 Prod-adjacent first cutovers: **1 step = 1 commit = 1 validation gate**. Once proven, subsequent hosts can absorb same N changes as one atomic commit.
- 🟡 Declarative-replaces-imperative migration: backup → activate → verify → strip unmanaged region. Redundancy over potential lockout.

---

*See also*: `/secrets`, `/nix`, `/ppm`, `/ops`. Full source: `AGENTS-CORE.md` topics `git/*`, `process/*`, `tools/{gh,just,zellij,script-design,shell-quoting,trash}`, `style/{file-operations,markdown-policy,naming-conventions}`.*
