# inspr-modules — Agent Doctrine Source

This repo is the **upstream canonical source** for INSPR agent doctrine. All
consuming repos (nixcfg, inspr, agm-com, ops) vendor it as `./doctrine/`
git submodule.

For Claude Code, the kernel auto-loads via `CLAUDE.md @-ref ./docs/AGENTS-KERNEL.md`. For other tools (Cursor, Aider, OpenCode, Codex CLI, Continue), the irreducible subset is mirrored below.

## Architecture (post-Phase-6, 2026-05-15)

| Layer | File | Loaded |
|---|---|---|
| **KERNEL** (always-on) | `docs/AGENTS-KERNEL.md` (budget ≤12 000 bytes, enforced by `inspr check`) | auto via CLAUDE.md @-ref |
| **DOMAIN packs** (on-demand) | `docs/AGENTS-DOMAIN-{DEV,IAC,NIX,OPS,PPM,SECRETS}.md` | via `/dev /iac /nix /ops /ppm /secrets` slash commands |
| **PROFILE** (on-demand) | `doctrine-private/docs/AGENTS-PROFILE-MARKUS.md` (full Markus profile) | via `/style` slash command |
| **AGENT role overlays** (on-demand) | `docs/AGENTS-AGENT-{SYSOP,SYSOP-GB,OPENCLAW-OPS,FLEET-DECISION,PPM,PPM-READONLY,DEV}.md` | via role-specific slash commands |
| **Reference** (on-demand) | `docs/AGENTS-CORE.md` (full universal-rules reference, 64k) | direct Read tool when exhaustive citation needed |
| **PER-REPO delta** (always-on) | `<repo>/AGENTS.md` in each consuming repo | auto via CLAUDE.md @-ref |

Run `/inspr` (in any consuming repo) for the TL;DR map of slash commands and architecture.

Index: [`docs/AGENTS-INDEX.md`](docs/AGENTS-INDEX.md) tracks all layer files + Phase 5 + Phase 6 commit refs.

<!-- KERNEL-MIRROR-BEGIN — auto-mirrored irreducible subset of docs/AGENTS-KERNEL.md (INSPR-191). For tools that read AGENTS.md but not the kernel via CLAUDE.md @-ref. -->

## Hard safety (kernel mirror — 🔴 only)

- 🔴 **Public library ≠ leak.** Some repos are deliberately public **ateliers** (identity-free primitives that private studio flakes consume, e.g. `inspr-modules`). Read a repo's `flake.nix` header before concluding anything about its visibility. Operator content in an atelier is fixed by moving the content, never by flipping the repo — it is load-bearing for consumers who are not you. Detail: `AGENTS-INDEX.md` § atelier pattern.
- 🔴 **Ticket first; identify the worker.** Before material work, bind the user-authorized scope to exactly one existing ticket in the product's designated PPM or PMA tracker, never both. If none exists, create it first. Before edits, commits, deployments, or other state changes, add `I work on this — session: <session-name> (<session-UUID>); role: <builder|reviewer|operator>; started: <ISO-8601>` for every participating agent or subagent; record later handoffs without erasing history. If a worker cannot write the tracker, its coordinator does both before dispatch; no marker means no material work. Markers contain no secrets and grant no approval. Read-only orientation/status checks are not material work. Detail: `AGENTS-CORE.md` § `workflow/work-attribution`.
- 🔴 **NEVER** run commands whose output IS the resolved environment: `direnv export`, `direnv status`, `set`, `declare -x/-p`, `compgen -e`, `export -p`, `env`, `printenv` (without naming a non-sensitive var), `docker inspect`, `docker exec … cat env`. Apply the **principle**, not just the literal list.
- 🔴 If a secret appears in any tool output: **STOP**. Do not reference, repeat or quote the value. Alert the operator. Treat as compromised; rotate before continuing.
- 🔴 Forbidden unless explicitly permitted: `git reset --hard`, `clean -f`, `restore .`, `checkout .`, `branch -D`, `rm`.
- 🔴 No `git push --force` to `main` / `master` without explicit ask.
- 🔴 No hook bypass (`--no-verify`, `--no-gpg-sign`) unless explicitly asked. On hook failure, fix the cause, restage, create a new commit. **Never `git commit --amend`** unless asked — the prior commit may have been the work you'd destroy.
- 🔴 Never commit secrets (passwords, API keys, tokens, bcrypt hashes, `.env` with real credentials, decrypted `.age` content). Before every commit: `git diff` to scan + `git status` to verify the file set.
- 🔴 Author changes **only in the session's own repo**. Everywhere else you propose, you don't edit: file a ticket in the owning project with the diff in the body. Reading foreign repos is unrestricted — only writes are governed.
- 🔴 Single carve-out — **release pins**: in a repo holding the deploy pin for what you just released, edit only the pin, its explanatory comment, and whatever that repo's documented vendoring step also requires (e.g. re-mirroring a doctrine block). Nothing else. Conditional on all of: **where a review path exists, use it (PR + checks — never a direct push to `main`, even where `main` is unprotected); where none exists, the owner's explicit request for that specific change is the gate — never agent initiative**; a recorded backup + rollback path; reversibility.
- 🔴 Third-party / business-owned repos are stricter: no PR path → **STOP and ask**, never push.
- 🔴 Clean up only your own residue. Branches you created in a foreign repo are yours to delete; anyone else's are a ticket, never `git push --delete`.
- 🔴 Deletes use `trash`, never `rm -rf`.
- 🔴 Don't delete or rename unexpected items — STOP and ask.
- 🔴 Touch encrypted files (`.age`, `.env`) only with explicit permission — hand the command to the operator rather than running it.
- 🔴 **NEVER build NixOS configs on macOS.** Build remotely via ssh. (macOS Home Manager configs CAN build locally.)
- 🔴 Never create new `.md` files unless explicitly asked; prefer editing an existing in-scope doc. **Durable knowledge → a PPM Knowledge entry** (architecture, rationale, positioning, playbooks, field notes, how-tos) when PPM writes are authorized (`/ppm` for mechanics), otherwise report the intended entry and ask. Stays local: `README`, `AGENTS.md` / `CLAUDE.md` + doctrine packs, `RUNBOOK.md`, `CHANGELOG.md`, `RESUMING-*`, `LICENSE`, code comments.

<!-- KERNEL-MIRROR-END -->
<!-- KERNEL-MIRROR-OF: sha256:1de3c58188decddd00f266a2234e496f5912a9327d1e24cccb43946fa7e5ea1f — attestation that the mirror block above reflects this exact kernel revision. Update via: sha256sum docs/AGENTS-KERNEL.md (enforced by the kernel-mirror-stamp flake check, INSPR-278). -->

## Editing rules

| Where | What |
|---|---|
| `docs/AGENTS-KERNEL.md` | new safety irreversibles or global protocol changes only (gatekeeper rule) |
| `docs/AGENTS-DOMAIN-<area>.md` | domain-specific workflow / technique / pattern |
| `doctrine-private/docs/AGENTS-PROFILE-MARKUS.md` | Markus's personal style / pacing preferences |
| `docs/AGENTS-AGENT-<ROLE>.md` | per-role overlays |
| `<repo>/AGENTS.md` (per consuming repo) | repo-specific delta |

After editing kernel: re-mirror the irreducible subset above by hand, then update the KERNEL-MIRROR-OF stamp below the mirror block (`sha256sum docs/AGENTS-KERNEL.md`) — the `kernel-mirror-stamp` flake check fails until you do (INSPR-278).

After editing anything in `docs/`: bump submodule pin in each consuming repo:

```sh
cd ~/Code/<repo>
git submodule update --remote doctrine
git commit doctrine -m "doctrine: bump to <short-sha>"
```
