<!--
  KERNEL — the only doctrine file that is auto-loaded into every Claude
  session opened in a Markus-INSPR repo (nixcfg, inspr, fleetcom,
  inspr-modules).  Domain-specific rules load on demand via slash
  commands — see ROUTER below.

  Hard size budget: ≤ 10 000 chars.  Phase 6 (INSPR-189) shipped 2026-05-15.
-->

# AGENTS — Kernel

_Layer: `kernel` · INSPR-189 Phase 6 · Auto-loaded · Universal hard-safety + identity + slash-command router._

This kernel is the always-on doctrine for every Claude agent in a Markus-INSPR repo. It carries ONLY rules where breaking them in turn 1 = immediate damage, plus the router for loading deeper context on demand. Everything else (style depth, nix patterns, git workflow, secrets pipeline, role overlays, …) lives in **domain packs** loaded via slash commands.

## Identity & protocol minimum

- **User**: Markus Barta — `markus@barta.com` — `markus-barta` on GitHub. Senior/founder framing (30 y dev, 15 y CEO, Graz). **Never invent identity placeholders.**
- **Workspace**: `~/Code/`. Repos under `github.com/markus-barta/<name>`. Third-party clones go to `~/Projects/3rdparty/`.
- **Shell**: fish (interactive). Use `bash -c '…'` wrappers when env-loading is needed (`set -a; source FILE; set +a` is bash-only).
- **Style**: telegraph, dense, low-fluff. **Long answers**: TL;DR at start AND end. **Short**: TL;DR at end only. **Very short**: omit TL;DR.
- **Pacing**: ONE STEP AT A TIME for interactive procedures (agenix, ssh handshakes, paimos auth, rotation flows). Wait for explicit "done" before next step. Never dump 5- or 10-step playbooks.
- **Default**: don't pick backlog items — ask Markus what to tackle.
- **Umbrella**: **INSPR** is the umbrella initiative; Paimos / FleetCom / future tools are inside it. Don't conflate. **BYTEPOETS** always all-caps (registered wordmark). **`.cm`** TLD is intentional, never auto-correct to `.com`.
- **Time awareness**: Before any time-of-day-coded greeting or farewell ("good evening", "have a good night", 🌙 / ☀️ emoji), run `date` once to anchor session time. Use accurate local time-of-day thereafter — OR prefer time-neutral closings ("cheers", "until next time", "see you", "—M"). Don't infer time-of-day from the date alone: knowing the date tells you nothing about whether it's morning or night.

## Hard safety irreversibles

### Secrets

- 🔴 Agent secrets live at `~/.inspr/secrets/agents/<NAME>.env` (canonical fleet-wide, INSPR-164). Source via `( set -a; source <file>; cmd; set +a )`. **NEVER `cat / Read / head / tail / less / bat / xxd / od / sed / grep / strings`** these files, or any file under `~/Secrets/`, `~/.ssh/<not-pub>`, `/run/agenix/`, `/run/secrets/`, or any `*.env`, `*.age`, `*.gpg`, `id_*`, `*_rsa`, `*_ed25519`.
- 🔴 **NEVER** run commands whose output IS the resolved environment: `direnv export`, `direnv status` (when active), `set`, `declare -x`, `declare -p`, `compgen -e`, `export -p`, `env`, `printenv` (without naming a specific non-sensitive var), `docker exec … cat env`, `kubectl describe configmap` after env expansion, `docker inspect`. Apply the **principle**, not just the literal list.
- 🔴 1Password is the canonical credential store. Don't propose alternative secret stores (sops, pass, env-vars-in-shell) unless explicitly asked to compare.
- 🔴 If a secret appears in any tool output: **STOP**. Do not reference, repeat, or quote the value. Alert the user immediately. Treat as compromised; rotate the credential before continuing.
- 🔴 To verify a secret EXISTS use `[ -n "$VAR" ] && echo set` or `ls -la <file>` only — never echo / cat / printf the value.

### Git

- 🔴 Destructive ops forbidden unless explicitly permitted: `git reset --hard`, `git clean -f`, `git restore .`, `git checkout .`, `git branch -D`, `git rm`.
- 🔴 No `git push --force` to `main` / `master` without explicit ask.
- 🔴 No hook bypass (`--no-verify`, `--no-gpg-sign`) unless explicitly asked. On hook failure, fix the underlying issue, restage, create a new commit. **Never `git commit --amend`** unless asked — the prior commit may have been the work you'd destroy.
- 🔴 Never commit secrets (passwords, API keys, tokens, bcrypt hashes, .env with real credentials, decrypted .age content). Before every commit: `git diff` to scan + `git status` to verify file set.
- 🟡 Push is part of normal flow on agreed changes — do it without asking.
- 🟡 In multi-agent repos, dirty files that aren't yours → `git stash push -- <paths>`, do your work, `git stash pop`. Don't `git stash` everything.

### Files & ops

- 🔴 For deletes use `trash`, never `rm -rf`.
- 🔴 Don't delete or rename unexpected items — STOP and ask.
- 🔴 Touch encrypted files (`.age`, `.env`) only with explicit permission. Provide commands for the user; don't run them yourself.
- 🔴 **NEVER build NixOS configs on macOS.** From macOS, build remotely via ssh. (macOS Home Manager configs CAN build locally.)
- 🔴 Never create new `.md` files unless explicitly asked. **Knowledge lives in PPM, not new `.md` files**: architecture, design rationale, positioning, playbooks, field notes, durable how-tos → create a PPM **Knowledge** entry (`/ppm` for mechanics), don't author a doc file. Stays local (must auto-load offline / repo-bound): `README`, `AGENTS.md`/`CLAUDE.md` + doctrine packs, `RUNBOOK.md`, `CHANGELOG.md`, `RESUMING-*`, `LICENSE`, code comments. Prefer editing an existing in-scope doc over creating one.

### Tooling minimum

- 🟡 `gh pr view/diff` for PRs — never paste GitHub URLs.
- 🟡 Terminal multiplexer: **zellij**, not tmux. Layouts in `~/.config/zellij/`.
- 🟡 Identity / git config lives declaratively in nixcfg — no `git config --global` without confirming first.
- 🟡 PPM: `paimos` CLI uses macOS Keychain (seeded once via `paimos auth login`; see `/ppm` for setup + non-macOS fallback). Raw curl uses env-file `~/.inspr/secrets/agents/PPMAPIKEY.env` (source it, never cat it).

## ROUTER — load context on demand

Before starting work in a domain, run the corresponding slash command. Each loads its full domain pack into your context.

| If you're about to…                                                  | Run               | Adds (~chars) |
| -------------------------------------------------------------------- | ----------------- | ------------- |
| Need a TL;DR map of all commands + doctrine                          | `/inspr`          | guide (~5k)   |
| Edit nix-darwin / Home Manager / devenv / NixOS module               | `/nix`            | ~10k          |
| Fleet ops, SSH between hosts, NixOS deploys (SYSOP role)             | `/ops`            | ~12k          |
| Touch agenix, 1P CLI, env-file pipeline, secrets rotation            | `/secrets`        | ~10k          |
| Declarative service config (Terraform / Zitadel / Cloudflare / etc.) | `/iac`            | ~8k           |
| Write/refactor code, run tests, do dev workflow                      | `/dev`            | ~8k           |
| Create / update PPM tickets, project planning                        | `/ppm`            | ~8k           |
| Need Markus's full style + pacing preferences in depth               | `/style`          | ~20k          |
| Handle a security incident or suspected secret leak                  | `/incident`       | ~5k           |
| Commit + push the current repo                                       | `/push`           | helper        |
| Commit + push across all workspace repos                             | `/pushall`        | helper        |
| OpenClaw bots ops (nixcfg-only)                                      | `/ocbots`         | OC ctx        |
| OpenClaw model cheat-sheet (nixcfg-only)                             | `/modelhelp`      | OC ref        |
| Update OC model lists (nixcfg-only)                                  | `/oc-modelupdate` | research      |

**Conflict resolution**: when multiple packs are loaded with conflicting rules on the same topic, the LATER `@-ref` wins (load order = precedence). KERNEL rules ALWAYS win over domain packs.

**Discoverability**: if you're uncertain which pack to load, run `/inspr` for the TL;DR map.

## Per-repo deltas

Each consuming repo has its own `AGENTS.md` at root with repo-specific rules (NixOS host quirks, fleetcom CLI conventions, etc.). The per-repo `AGENTS.md` is auto-loaded alongside this kernel via `CLAUDE.md`.

## Gatekeeper rule (Phase 6 design intent)

**The kernel grows ONLY for**:

1. New safety irreversibles (would prevent immediate damage in turn 1)
2. New global protocol changes affecting every agent in every repo
3. New slash commands (router updates)

Everything else — domain knowledge, role-specific rules, technique notes, style preferences — goes to a **domain pack**. Don't add a rule to the kernel that could live elsewhere. Default to a domain pack; promote to kernel only when the cost of NOT having it always-loaded exceeds the auto-load cost.

---

_Cross-references: `/inspr` for the full doctrine guide. Phase 6 (INSPR-189) introduced this kernel on 2026-05-15. Pre-Phase-6 sessions auto-loaded ~127 k chars; post-Phase-6 ≤25 k. Layered file index in `inspr-modules/docs/AGENTS-INDEX.md`. Comprehensive (now-on-demand) source files: `AGENTS-CORE.md` (universal reference), `AGENTS-PROFILE-MARKUS.md` (full profile), `AGENTS-AGENT-*.md` (role overlays)._
