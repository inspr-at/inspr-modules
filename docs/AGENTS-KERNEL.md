<!-- PUBLIC KERNEL — auto-loaded in every consuming repo. Budget 12 000 BYTES (`wc -c`; emoji are multibyte), enforced by `inspr check`. Editing rules + history: AGENTS-INDEX.md. -->

# AGENTS — Kernel

_Auto-loaded. Universal hard-safety + identity + router. Carries ONLY rules where breaking them in turn 1 = immediate damage; everything else lives in **domain packs** behind slash commands._

## Identity & protocol

- 🔴 **Public library ≠ leak.** Some repos are deliberately public **ateliers** (identity-free primitives that private studio flakes consume, e.g. `inspr-modules`). Read a repo's `flake.nix` header before concluding anything about its visibility. Operator content in an atelier is fixed by moving the content, never by flipping the repo — it is load-bearing for consumers who are not you. Detail: `AGENTS-INDEX.md` § atelier pattern.
- 🔴 **Ticket first; identify the worker.** Before material work, bind the user-authorized scope to exactly one existing ticket in the product's designated PPM or PMA tracker, never both. If none exists, create it first. Before edits, commits, deployments, or other state changes, add `I work on this — session: <session-name> (<session-UUID>); role: <builder|reviewer|operator>; started: <ISO-8601>` for every participating agent or subagent; record later handoffs without erasing history. Markers contain no secrets and grant no approval. Read-only orientation/status checks are not material work. Detail: `AGENTS-CORE.md` § `workflow/work-attribution`.

## Hard safety irreversibles

### Secrets

- 🔴 **NEVER** run commands whose output IS the resolved environment: `direnv export`, `direnv status`, `set`, `declare -x/-p`, `compgen -e`, `export -p`, `env`, `printenv` (without naming a non-sensitive var), `docker inspect`, `docker exec … cat env`. Apply the **principle**, not just the literal list.
- 🔴 If a secret appears in any tool output: **STOP**. Do not reference, repeat or quote the value. Alert the operator. Treat as compromised; rotate before continuing.

### Git

- 🔴 Forbidden unless explicitly permitted: `git reset --hard`, `clean -f`, `restore .`, `checkout .`, `branch -D`, `rm`.
- 🔴 No `git push --force` to `main` / `master` without explicit ask.
- 🔴 No hook bypass (`--no-verify`, `--no-gpg-sign`) unless explicitly asked. On hook failure, fix the cause, restage, create a new commit. **Never `git commit --amend`** unless asked — the prior commit may have been the work you'd destroy.
- 🔴 Never commit secrets (passwords, API keys, tokens, bcrypt hashes, `.env` with real credentials, decrypted `.age` content). Before every commit: `git diff` to scan + `git status` to verify the file set.

### Cross-repo authoring

- 🔴 Author changes **only in the session's own repo**. Everywhere else you propose, you don't edit: file a ticket in the owning project with the diff in the body. Reading foreign repos is unrestricted — only writes are governed.
- 🔴 Single carve-out — **release pins**: in a repo holding the deploy pin for what you just released, edit only the pin, its explanatory comment, and whatever that repo's documented vendoring step also requires (e.g. re-mirroring a doctrine block). Nothing else. Conditional on all of: **where a review path exists, use it (PR + checks — never a direct push to `main`, even where `main` is unprotected); where none exists, the owner's explicit request for that specific change is the gate — never agent initiative**; a recorded backup + rollback path; reversibility.
- 🔴 Third-party / business-owned repos are stricter: no PR path → **STOP and ask**, never push.
- 🔴 Clean up only your own residue. Branches you created in a foreign repo are yours to delete; anyone else's are a ticket, never `git push --delete`.
- 🟡 Depth, and the incidents behind this rule, belong in the operator's own private ops notes; this kernel states the rule, not the war stories.

### Files & ops

- 🔴 Deletes use `trash`, never `rm -rf`.
- 🔴 Don't delete or rename unexpected items — STOP and ask.
- 🔴 Touch encrypted files (`.age`, `.env`) only with explicit permission — hand the command to the operator rather than running it.
- 🔴 **NEVER build NixOS configs on macOS.** Build remotely via ssh. (macOS Home Manager configs CAN build locally.)
- 🔴 Never create new `.md` files unless explicitly asked; prefer editing an existing in-scope doc. **Durable knowledge → a PPM Knowledge entry** (architecture, rationale, positioning, playbooks, field notes, how-tos) when PPM writes are authorized (`/ppm` for mechanics), otherwise report the intended entry and ask. Stays local: `README`, `AGENTS.md` / `CLAUDE.md` + doctrine packs, `RUNBOOK.md`, `CHANGELOG.md`, `RESUMING-*`, `LICENSE`, code comments.

## ROUTER — load before working in a domain

`/inspr` map · `/nix` nix-darwin + HM + NixOS modules · `/dev` code + tests + git workflow · `/push`

Studio repos also load a private kernel, which adds `/ppm` `/ops` `/iac` `/secrets` `/style` `/incident`.

Budget before loading — heavy: `/style` ≈46k · `/ppm` ≈22k · `/incident` ≈20k · `/ops` ≈18k. The rest are 9–11k. nixcfg adds repo-local `/ocbots`, `/modelhelp`, `/oc-modelupdate`.

**Precedence**: later `@-ref` wins; KERNEL always wins over domain packs. Each repo also auto-loads its own delta (`AGENTS.md`, or `AGENTS-NIXCFG.md` in nixcfg).

## Gatekeeper

Kernel grows ONLY for a new turn-1 irreversible, a global protocol change, or a router update. Everything else → a domain pack. Full rule: `AGENTS-INDEX.md`.
