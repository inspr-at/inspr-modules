<!-- KERNEL — auto-loaded in every Markus-INSPR repo. Budget 12 000 BYTES (`wc -c`; emoji are multibyte), enforced by `inspr check`. Editing rules + history: AGENTS-INDEX.md. -->

# AGENTS — Kernel

_Auto-loaded. Universal hard-safety + identity + router. Carries ONLY rules where breaking them in turn 1 = immediate damage; everything else lives in **domain packs** behind slash commands._

## Identity & protocol

- **User**: Markus Barta — `markus@barta.com` — `markus-barta` on GitHub. Senior/founder framing (30 y dev, 15 y CEO, Graz). **Never invent identity placeholders.**
- **Workspace**: `~/Code/`. Repos under `github.com/markus-barta/<name>`. Third-party clones → `~/Projects/3rdparty/`.
- **Shell**: fish (interactive). Use `bash -c '…'` when env-loading is needed (`set -a; source FILE; set +a` is bash-only).
- **Style**: telegraph, dense, low-fluff. Long answers: TL;DR at start AND end. Short: TL;DR at end only. Very short: omit.
- **Pacing**: ONE STEP AT A TIME for interactive procedures (agenix, ssh handshakes, paimos auth, rotation flows). Wait for explicit "done". Never dump 5- or 10-step playbooks.
- **Default**: don't pick backlog items — ask Markus what to tackle.
- **Time**: the date alone tells you nothing about morning vs night. Run `date` before any time-of-day greeting or farewell, or stay time-neutral.
- **Umbrella**: **INSPR** is the umbrella; Paimos / Pharos / Janus sit inside it (FleetCom archived → Pharos). **`.cm`** TLD intentional, never `.com`.
- 🔴 **Trust contexts**: every repo is **personal**, **INSPR** (FOSS, `inspr-at`) or **augmentoring** (business side — client work, e.g. `dsccfg`) — classify by **ownership of the output**, never by GitHub org. **Never cross contexts with credentials or tickets** (`dsccfg`→`DSC26`, personal→`OPS`); STOP and ask. Detail: INSPR guidelines `trust-contexts` (repos) + `domain-separation-barta-vs-augmentoring` (domains).

## Hard safety irreversibles

### Secrets

- 🔴 Agent secrets live at `~/.inspr/secrets/agents/<NAME>.env` (INSPR-164). Source via `( set -a; source <file>; cmd; set +a )`. **NEVER `cat / Read / head / tail / less / bat / xxd / od / sed / grep / strings`** these, or anything under `~/Secrets/`, `~/.ssh/<not-pub>`, `/run/agenix/`, `/run/secrets/`, or any `*.env`, `*.age`, `*.gpg`, `id_*`, `*_rsa`, `*_ed25519`. To confirm one exists: `[ -n "$VAR" ] && echo set` or `ls -la <file>` — never echo / cat / printf the value.
- 🔴 **NEVER** run commands whose output IS the resolved environment: `direnv export`, `direnv status`, `set`, `declare -x/-p`, `compgen -e`, `export -p`, `env`, `printenv` (without naming a non-sensitive var), `docker inspect`, `docker exec … cat env`. Apply the **principle**, not just the literal list.
- 🔴 1Password is the canonical credential store. Don't propose alternatives (sops, pass, env-vars-in-shell) unless explicitly asked to compare.
- 🔴 If a secret appears in any tool output: **STOP**. Do not reference, repeat or quote the value. Alert Markus. Treat as compromised; rotate before continuing.

### Git

- 🔴 Forbidden unless explicitly permitted: `git reset --hard`, `clean -f`, `restore .`, `checkout .`, `branch -D`, `rm`.
- 🔴 No `git push --force` to `main` / `master` without explicit ask.
- 🔴 No hook bypass (`--no-verify`, `--no-gpg-sign`) unless explicitly asked. On hook failure, fix the cause, restage, create a new commit. **Never `git commit --amend`** unless asked — the prior commit may have been the work you'd destroy.
- 🔴 Never commit secrets (passwords, API keys, tokens, bcrypt hashes, `.env` with real credentials, decrypted `.age` content). Before every commit: `git diff` to scan + `git status` to verify the file set.

### Files & ops

- 🔴 Deletes use `trash`, never `rm -rf`.
- 🔴 Don't delete or rename unexpected items — STOP and ask.
- 🔴 Touch encrypted files (`.age`, `.env`) only with explicit permission — give Markus the command, don't run it yourself.
- 🔴 **NEVER build NixOS configs on macOS.** Build remotely via ssh. (macOS Home Manager configs CAN build locally.)
- 🔴 Never create new `.md` files unless explicitly asked; prefer editing an existing in-scope doc. **Durable knowledge → a PPM Knowledge entry** (architecture, rationale, positioning, playbooks, field notes, how-tos) when PPM writes are authorized (`/ppm` for mechanics), otherwise report the intended entry and ask. Stays local: `README`, `AGENTS.md` / `CLAUDE.md` + doctrine packs, `RUNBOOK.md`, `CHANGELOG.md`, `RESUMING-*`, `LICENSE`, code comments.

## ROUTER — load before working in a domain

`/inspr` map · `/nix` nix-darwin + HM + NixOS modules · `/ops` fleet + SSH + deploys (SYSOP) · `/secrets` agenix + 1P + env pipeline · `/iac` Terraform / Zitadel / Cloudflare · `/dev` code + tests + git workflow · `/ppm` tickets + planning · `/style` full Markus profile · `/incident` leak protocol · `/push` · `/pushall`

Budget before loading — heavy: `/style` ≈46k · `/ppm` ≈22k · `/incident` ≈20k · `/ops` ≈18k. The rest are 9–11k. nixcfg adds repo-local `/ocbots`, `/modelhelp`, `/oc-modelupdate`.

**Precedence**: later `@-ref` wins; KERNEL always wins over domain packs. Each repo also auto-loads its own delta (`AGENTS.md`, or `AGENTS-NIXCFG.md` in nixcfg).

## Gatekeeper

Kernel grows ONLY for a new turn-1 irreversible, a global protocol change, or a router update. Everything else → a domain pack. Full rule: `AGENTS-INDEX.md`.
