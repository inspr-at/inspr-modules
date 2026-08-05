# inspr-modules — Agent Doctrine Source

This repo is the **upstream canonical source** for INSPR agent doctrine. All
consuming repos (nixcfg, inspr, amt-com, ops) vendor it as `./doctrine/`
git submodule.

For Claude Code, the kernel auto-loads via `CLAUDE.md @-ref ./docs/AGENTS-KERNEL.md`. For other tools (Cursor, Aider, OpenCode, Codex CLI, Continue), the irreducible subset is mirrored below.

## Architecture (post-Phase-6, 2026-05-15)

| Layer | File | Loaded |
|---|---|---|
| **KERNEL** (always-on) | `docs/AGENTS-KERNEL.md` (budget ≤12 000 bytes, enforced by `inspr check`) | auto via CLAUDE.md @-ref |
| **DOMAIN packs** (on-demand) | `docs/AGENTS-DOMAIN-{DEV,IAC,NIX,OPS,PPM,SECRETS}.md` | via `/dev /iac /nix /ops /ppm /secrets` slash commands |
| **PROFILE** (on-demand) | `docs/AGENTS-PROFILE-MARKUS.md` (full Markus profile) | via `/style` slash command |
| **AGENT role overlays** (on-demand) | `docs/AGENTS-AGENT-{SYSOP,SYSOP-GB,OPENCLAW-OPS,FLEET-DECISION,PPM,PPM-READONLY,DEV}.md` | via role-specific slash commands |
| **Reference** (on-demand) | `docs/AGENTS-CORE.md` (full universal-rules reference, 64k) | direct Read tool when exhaustive citation needed |
| **PER-REPO delta** (always-on) | `<repo>/AGENTS.md` in each consuming repo | auto via CLAUDE.md @-ref |

Run `/inspr` (in any consuming repo) for the TL;DR map of slash commands and architecture.

Index: [`docs/AGENTS-INDEX.md`](docs/AGENTS-INDEX.md) tracks all layer files + Phase 5 + Phase 6 commit refs.

<!-- KERNEL-MIRROR-BEGIN — auto-mirrored irreducible subset of docs/AGENTS-KERNEL.md (INSPR-191). For tools that read AGENTS.md but not the kernel via CLAUDE.md @-ref. -->

## Universal must-knows (kernel mirror)

- **Identity**: Markus Barta, `markus@barta.com`, `markus-barta` on GitHub. Never invent placeholders.
- **Workspace**: `~/Code/`. Repos under `github.com/markus-barta/<name>`. Third-party clones go to `~/Projects/3rdparty/`.
- **Time awareness**: Run `date` before any time-of-day-coded greeting/farewell ("good evening", 🌙 / ☀️). Knowing the date alone tells you nothing about morning/night. Prefer time-neutral closings ("cheers", "until next time") if a check would be disruptive.
- **Style**: telegraph, dense, low-fluff. **Long** answers: TL;DR at start AND end. **Short**: TL;DR at end only. **Very short**: omit TL;DR.
- **Pacing**: ONE STEP AT A TIME for interactive procedures (agenix, ssh, paimos auth, rotation flows). Wait for explicit "done" before next step. Never dump 5- or 10-step playbooks.
- **Secrets**: NEVER `cat / Read / head / tail / less / bat / xxd / od / sed / grep / strings` files in `~/.inspr/secrets/agents/`, `~/Secrets/`, `~/.ssh/<not-pub>`, `/run/agenix/`, `/run/secrets/`, or any `*.env` / `*.age` / `*.gpg` / `id_*` / `*_rsa` / `*_ed25519`. Source via `( set -a; source FILE; cmd; set +a )`. NEVER run `direnv export`, `direnv status`, `set`, `declare -x/-p`, `compgen -e`, `export -p`, bare `env` / `printenv`, `docker inspect`, `docker exec ... cat env`, `kubectl describe configmap` after env expansion — apply the **principle** (output IS the resolved environment), not just the literal list. If a secret appears in output: **STOP**, name affected vars (not values), rotate before continuing.
- **Git**: never `reset --hard` / `clean -f` / `restore .` / `branch -D` / `rm` unless asked. Never `--force` push main. Never `--no-verify` / `--no-gpg-sign` / `--amend` unless asked. Never commit secrets (passwords, API keys, .env with real creds, decrypted .age content). `git diff` + `git status` before every commit.
- **Files & ops**: use `trash` not `rm -rf`. Don't delete or rename unexpected items — STOP and ask. Touch encrypted files only with explicit permission. **NEVER build NixOS configs on macOS** (build remotely via ssh; macOS HM CAN build locally). Never create new `.md` files unless asked.
- **Naming**: **`.cm`** TLD intentional, never auto-correct to `.com`. **INSPR** is the umbrella; Paimos / Pharos / Janus / future tools are inside it (FleetCom is archived, superseded by Pharos).
- 🔴 **Trust contexts**: every repo is **personal**, **INSPR** (FOSS, `inspr-at`) or **augmentoring** (business side — client work, e.g. `dsccfg`) — classify by **ownership of the output**, never by GitHub org. **Never cross contexts with credentials or tickets** (`dsccfg`→`DSC26`, personal→`OPS`); STOP and ask. Detail: INSPR PPM guidelines `trust-contexts` + `domain-separation-barta-vs-augmentoring`.

For full kernel: see [`docs/AGENTS-KERNEL.md`](docs/AGENTS-KERNEL.md). For depth: load the relevant domain pack via slash command (`/dev /iac /nix /ops /ppm /secrets /style /incident`). Run `/inspr` for the TL;DR map.

<!-- KERNEL-MIRROR-END -->

## Editing rules

| Where | What |
|---|---|
| `docs/AGENTS-KERNEL.md` | new safety irreversibles or global protocol changes only (gatekeeper rule) |
| `docs/AGENTS-DOMAIN-<area>.md` | domain-specific workflow / technique / pattern |
| `docs/AGENTS-PROFILE-MARKUS.md` | Markus's personal style / pacing preferences |
| `docs/AGENTS-AGENT-<ROLE>.md` | per-role overlays |
| `<repo>/AGENTS.md` (per consuming repo) | repo-specific delta |

After editing kernel: re-mirror the irreducible subset above by hand, OR (future) run a build script when one exists.

After editing anything in `docs/`: bump submodule pin in each consuming repo:

```sh
cd ~/Code/<repo>
git submodule update --remote doctrine
git commit doctrine -m "doctrine: bump to <short-sha>"
```
