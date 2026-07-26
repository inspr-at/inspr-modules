<!--
  KERNEL — the only doctrine file auto-loaded into every Claude session
  opened in a Markus-INSPR repo (nixcfg, inspr, inspr-modules, ops).
  Domain rules load on demand via slash commands — see ROUTER below.

  Hard size budget: 12 000 BYTES, enforced by `inspr check`
  (check_doctrine_kernel_size_budget). Measure with `wc -c`, NOT a
  character count — the 🔴/🟡 emoji are multibyte, so the two differ by
  ~130. Editing rules and Phase-6 history: AGENTS-INDEX.md.
-->

# AGENTS — Kernel

_Layer: `kernel` · Auto-loaded · Universal hard-safety + identity + slash-command router. Carries ONLY rules where breaking them in turn 1 = immediate damage; everything else (style depth, nix patterns, git workflow, secrets pipeline, role overlays, …) lives in **domain packs** loaded via slash commands._

## Identity & protocol minimum

- **User**: Markus Barta — `markus@barta.com` — `markus-barta` on GitHub. Senior/founder framing (30 y dev, 15 y CEO, Graz). **Never invent identity placeholders.**
- **Workspace**: `~/Code/`. Repos under `github.com/markus-barta/<name>`. Third-party clones go to `~/Projects/3rdparty/`.
- **Shell**: fish (interactive). Use `bash -c '…'` wrappers when env-loading is needed (`set -a; source FILE; set +a` is bash-only).
- **Style**: telegraph, dense, low-fluff. **Long answers**: TL;DR at start AND end. **Short**: TL;DR at end only. **Very short**: omit TL;DR.
- **Pacing**: ONE STEP AT A TIME for interactive procedures (agenix, ssh handshakes, paimos auth, rotation flows). Wait for explicit "done" before next step. Never dump 5- or 10-step playbooks.
- **Default**: don't pick backlog items — ask Markus what to tackle.
- **Umbrella & trust contexts**: **INSPR** is the umbrella; Paimos / Pharos / Janus sit inside it (FleetCom archived → Pharos). Every repo is exactly one of **personal** (own infra + hobby), **INSPR** (FOSS, `inspr-at`), or **augmentoring** (INSPR's business side — client work, e.g. `dsccfg`). Classify by **ownership of the output**, never by GitHub org — orgs don't match the split yet. 🔴 Never cross contexts with credentials or tickets (`dsccfg`→`DSC26`, personal→`OPS`); STOP and ask. Detail: INSPR guideline `trust-contexts`. **`.cm`** TLD intentional, never `.com`.
- **Time awareness**: the date alone tells you nothing about morning vs night. Run `date` before any time-of-day greeting or farewell ("good evening", 🌙 / ☀️), or use time-neutral closings.

## Hard safety irreversibles

### Secrets

- 🔴 Agent secrets live at `~/.inspr/secrets/agents/<NAME>.env` (canonical fleet-wide, INSPR-164). Source via `( set -a; source <file>; cmd; set +a )`. **NEVER `cat / Read / head / tail / less / bat / xxd / od / sed / grep / strings`** these files, or anything under `~/Secrets/`, `~/.ssh/<not-pub>`, `/run/agenix/`, `/run/secrets/`, or any `*.env`, `*.age`, `*.gpg`, `id_*`, `*_rsa`, `*_ed25519`. To confirm one EXISTS: `[ -n "$VAR" ] && echo set` or `ls -la <file>` — never echo / cat / printf the value.
- 🔴 **NEVER** run commands whose output IS the resolved environment: `direnv export`, `direnv status`, `set`, `declare -x/-p`, `compgen -e`, `export -p`, `env`, `printenv` (without naming a non-sensitive var), `docker inspect`, `docker exec … cat env`. Apply the **principle**, not just the literal list.
- 🔴 1Password is the canonical credential store. Don't propose alternatives (sops, pass, env-vars-in-shell) unless explicitly asked to compare.
- 🔴 If a secret appears in any tool output: **STOP**. Do not reference, repeat, or quote the value. Alert Markus immediately. Treat as compromised; rotate before continuing.

### Git

- 🔴 Destructive ops forbidden unless explicitly permitted: `git reset --hard`, `git clean -f`, `git restore .`, `git checkout .`, `git branch -D`, `git rm`.
- 🔴 No `git push --force` to `main` / `master` without explicit ask.
- 🔴 No hook bypass (`--no-verify`, `--no-gpg-sign`) unless explicitly asked. On hook failure, fix the underlying issue, restage, create a new commit. **Never `git commit --amend`** unless asked — the prior commit may have been the work you'd destroy.
- 🔴 Never commit secrets (passwords, API keys, tokens, bcrypt hashes, `.env` with real credentials, decrypted `.age` content). Before every commit: `git diff` to scan + `git status` to verify the file set.

### Files & ops

- 🔴 For deletes use `trash`, never `rm -rf`.
- 🔴 Don't delete or rename unexpected items — STOP and ask.
- 🔴 Touch encrypted files (`.age`, `.env`) only with explicit permission. Provide the commands for Markus; don't run them yourself.
- 🔴 **NEVER build NixOS configs on macOS.** From macOS, build remotely via ssh. (macOS Home Manager configs CAN build locally.)
- 🔴 Never create new `.md` files unless explicitly asked; prefer editing an existing in-scope doc. **Durable knowledge belongs in PPM** — architecture, design rationale, positioning, playbooks, field notes, how-tos → a PPM **Knowledge** entry when PPM writes are authorized (`/ppm` for mechanics), otherwise report the intended entry and ask. Stays local (must auto-load offline): `README`, `AGENTS.md`/`CLAUDE.md` + doctrine packs, `RUNBOOK.md`, `CHANGELOG.md`, `RESUMING-*`, `LICENSE`, code comments.

## ROUTER — load context on demand

Before starting work in a domain, run its slash command to load the pack.

| If you're about to…                                                  | Run                  |
| -------------------------------------------------------------------- | -------------------- |
| Need a TL;DR map of all commands + doctrine                          | `/inspr`             |
| Edit nix-darwin / Home Manager / devenv / NixOS module               | `/nix`               |
| Fleet ops, SSH between hosts, NixOS deploys (SYSOP role)             | `/ops`               |
| Touch agenix, 1P CLI, env-file pipeline, secrets rotation            | `/secrets`           |
| Declarative service config (Terraform / Zitadel / Cloudflare / etc.) | `/iac`               |
| Write/refactor code, run tests, do dev workflow                      | `/dev`               |
| Create / update PPM tickets, project planning                        | `/ppm`               |
| Need Markus's full style + pacing preferences in depth               | `/style`             |
| Handle a security incident or suspected secret leak                  | `/incident`          |
| Commit + push this repo / every workspace repo                       | `/push` · `/pushall` |

Budget before loading — the heavy ones: `/style` ≈46k, `/ppm` ≈22k, `/incident` ≈20k, `/ops` ≈18k. The rest are 9–11k. nixcfg adds repo-local `/ocbots`, `/modelhelp`, `/oc-modelupdate`.

**Conflict resolution**: when packs conflict on a topic, the LATER `@-ref` wins (load order = precedence). KERNEL rules ALWAYS win over domain packs. Each repo's own `AGENTS.md` is auto-loaded alongside this kernel and carries its local delta.

## Gatekeeper

The kernel grows ONLY for a new turn-1 safety irreversible, a global protocol change affecting every agent in every repo, or a router update. Everything else — domain knowledge, role rules, technique notes, style preferences — goes to a **domain pack**. Full rule, layered file index, and Phase-6 history: `AGENTS-INDEX.md`.
