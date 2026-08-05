# /inspr — INSPR doctrine & slash-command guide

TL;DR map of available slash commands and what each loads. Run `/inspr` anytime you're not sure which context to pull in.

## What is INSPR?

Markus Barta's umbrella initiative — broader than Paimos. Mission: _"inspiration is the only limit."_

All agent doctrine for `~/Code/{nixcfg,inspr,amt-com,ops,inspr-modules}` is published from the **`inspr-modules`** repo and vendored as `./doctrine/` git submodule in each consuming repo. Per-repo deltas live in `<repo>/AGENTS.md`.

## Doctrine architecture (post-Phase-6, 2026-05-15)

Three tiers:

1. **KERNEL** (`AGENTS-KERNEL.md`, currently ~5.5 k; budget ≤12 000 bytes, `wc -c`, enforced by `inspr check`) — auto-loaded by `CLAUDE.md @-ref` in every session. Carries hard-safety irreversibles + identity + slash-command router. ALWAYS in context.
2. **DOMAIN PACKS** (`AGENTS-DOMAIN-*.md`, ~5–10 k each) — loaded **on demand** when you run a slash command. Each pack contains depth, technique, and workflow guidance for one area (secrets, nix, dev, ops, ppm).
3. **PER-REPO DELTA** (`<repo>/AGENTS.md`) — auto-loaded alongside kernel via `CLAUDE.md @-ref`. Carries repo-specific rules unique to nixcfg / inspr / amt-com / ops.

### Comprehensive references (also on-demand)

- `AGENTS-CORE.md` — full universal-rules reference (199 rules, 64 k chars). Source for the kernel's safety subset; load if you need exhaustive citation.
- `AGENTS-PROFILE-MARKUS.md` — Markus's full profile (153 rules, 47 k chars). Loaded by `/style`.
- `AGENTS-AGENT-*.md` — per-role overlays (SYSOP, SYSOP-GB, OPENCLAW-OPS, FLEET-DECISION, PPM, PPM-READONLY, DEV). Loaded by relevant slash commands.

**Pre-Phase-6 budget**: ~127 k chars auto-loaded per session in nixcfg.
**Post-Phase-6 auto-load**: kernel + per-repo AGENTS.md. The kernel is budgeted (≤12 000 bytes, enforced); per-repo deltas are not — measured sizes and the audit history live in `AGENTS-INDEX.md` (the original "≤25 k combined" claim was debunked there 2026-07-26).

## Slash commands

| Command            | What it loads (on demand)                                            | When to use                                              |
| ------------------ | -------------------------------------------------------------------- | -------------------------------------------------------- |
| `/inspr`           | This guide                                                           | Anytime you need the map                                 |
| `/dev`             | `AGENTS-DOMAIN-DEV.md`                                               | Code, tests, refactor, git workflow depth                |
| `/ops`             | `AGENTS-DOMAIN-OPS.md` + `AGENTS-AGENT-SYSOP.md`                     | Fleet ops, SSH between hosts, NixOS deploys              |
| `/secrets`         | `AGENTS-DOMAIN-SECRETS.md`                                           | agenix, 1P CLI, env-file pipeline, secrets rotation      |
| `/nix`             | `AGENTS-DOMAIN-NIX.md`                                               | nix-darwin, Home Manager, devenv, NixOS modules          |
| `/iac`             | `AGENTS-DOMAIN-IAC.md`                                               | Terraform, Zitadel, Cloudflare — L5 declarative services |
| `/ppm`             | `AGENTS-DOMAIN-PPM.md` + `AGENTS-AGENT-PPM.md`                       | Project planning, ticket triage, dashboards              |
| `/style`           | `AGENTS-PROFILE-MARKUS.md`                                           | Need Markus's full style + pacing prefs in depth         |
| `/incident`        | Incident-response section of CORE + secret-leak protocol             | Security incident, suspected secret leak                 |
| `/push`            | Single-repo commit + push helper                                     | Wrap up a single-repo change                             |
| `/pushall`         | Multi-repo dispatch                                                  | Cross-repo commits in one go                             |
| `/ocbots`          | OpenClaw bots ops context                                            | OC bot deploy / admin                                    |
| `/modelhelp`       | OpenClaw model cheat-sheet                                           | Quick reference for OC models                            |
| `/oc-modelupdate`  | Research + update model lists                                        | Refresh OC model catalog                                 |

## Key references

- **Doctrine source**: <https://github.com/inspr-at/inspr-modules/tree/main/docs>
- **PPM** (project tracker): <https://pm.barta.cm> — INSPR project key, `/ppm` for ops
- **Fleet inventory**: **Pharos** — <https://pharos.barta.cm> (canonical live machine list; HostDash for the human view). Never assume static lists.
- **Field notes / runbooks**: per-repo `docs/`
- **Agent secrets**: `~/.inspr/secrets/agents/*.env` — load via env, **never cat / Read / display**

## Adding new doctrine

| Where it goes                                            | What it is                                                         |
| -------------------------------------------------------- | ------------------------------------------------------------------ |
| `inspr-modules/docs/AGENTS-KERNEL.md`                    | New safety irreversibles or new global protocol changes only       |
| `inspr-modules/docs/AGENTS-DOMAIN-<area>.md`             | Domain-specific workflow, technique, or pattern                    |
| `inspr-modules/docs/AGENTS-PROFILE-MARKUS.md`            | Markus's personal style / pacing preferences                       |
| `inspr-modules/docs/AGENTS-AGENT-<ROLE>.md`              | Per-role overlays (SYSOP, PPM, DEV, …)                             |
| `<repo>/AGENTS.md`                                       | Per-repo delta unique to that repo                                 |

**Gatekeeper rule**: the kernel grows ONLY for new safety irreversibles, new global protocol changes, or new slash commands (router updates). Everything else goes to a domain pack. Default to a domain pack; promote to kernel only when the cost of NOT having it always-loaded exceeds the auto-load cost.

After upstream change, bump submodule in each consuming repo:

```sh
cd ~/Code/<repo>
git submodule update --remote doctrine
git commit doctrine -m "doctrine: bump to <short-sha>"
```

## How `/inspr` itself stays in sync

`/inspr.md` lives canonically in `inspr-modules/commands/inspr.md` and is symlinked into each consuming repo's `+agents/commands/` (nixcfg) or `.claude/commands/` (inspr, amt-com, ops) directory through the `./doctrine/` submodule. Edit it once upstream, bump the submodule, every repo gets the update.
