# /inspr — INSPR doctrine & slash-command guide

TL;DR map of available slash commands and what each loads. Run `/inspr` anytime you're not sure which context to pull in.

## What is INSPR?

Markus Barta's umbrella initiative — broader than Paimos. Mission: _"inspiration is the only limit."_

All agent doctrine for `~/Code/{nixcfg,inspr,fleetcom,inspr-modules}` is published from the **`inspr-modules`** repo and vendored as `./doctrine/` git submodule in each consuming repo. Per-repo deltas live in `<repo>/AGENTS.md`.

## Doctrine layers (auto-loaded at session start)

Every Claude session in nixcfg / fleetcom / inspr / inspr-modules loads these via `CLAUDE.md` `@-refs`:

1. **AGENTS-CORE.md** — universal rules (security irreversibles, identity, protocol)
2. **AGENTS-PROFILE-MARKUS.md** — Markus's style + pacing preferences
3. **`<repo>/AGENTS.md`** — repo-specific delta (nixcfg: 55 rules · fleetcom: 26 · inspr: 0)

> ⚠ **Phase 6 incoming (INSPR-189):** today's auto-load is ~127 k chars / ~32 k tokens. Phase 6 will trim to <10 % of that via a lean **KERNEL** + on-demand **DOMAIN PACKS**. `/inspr` becomes the always-available router.

## Slash commands — current

| Command            | What it loads                                             | When to use                                  |
| ------------------ | --------------------------------------------------------- | -------------------------------------------- |
| `/inspr`           | This guide                                                | Anytime you need the map                     |
| `/ops`             | SYSOP role overlay + nixcfg AGENTS.md                     | Fleet ops, SSH between hosts, NixOS deploys  |
| `/ppm`             | PPM API context (read-only mode)                          | Project planning, ticket triage, dashboards  |
| `/push`            | Single-repo commit + push helper                          | Wrap up a single-repo change                 |
| `/pushall`         | Multi-repo dispatch                                       | Cross-repo commits in one go                 |
| `/ocbots`          | OpenClaw bots ops context                                 | OC bot deploy / admin                        |
| `/modelhelp`       | OpenClaw model cheat-sheet                                | Quick reference for OC models                |
| `/oc-modelupdate`  | Research + update model lists                             | Refresh OC model catalog                     |

## Slash commands — planned (Phase 6, not yet built)

| Planned       | Will load                                              |
| ------------- | ------------------------------------------------------ |
| `/dev`        | DEV role + dev-domain rules (git, tests, code style)   |
| `/secrets`    | Agenix flow + 1P CLI + env-file pattern deep-dive      |
| `/nix`        | nix-darwin + Home Manager + devenv patterns            |
| `/style`      | Full Markus profile (deeper than KERNEL load)          |
| `/incident`   | Emergency response protocol                            |

## Key references

- **Doctrine source**: <https://github.com/markus-barta/inspr-modules/tree/main/docs>
- **PPM** (project tracker): <https://pm.barta.cm> — INSPR project key, `/ppm` for ops
- **Fleet inventory**: `~/Code/fleetcom` (canonical machine list)
- **Field notes / runbooks**: per-repo `docs/`
- **Agent secrets**: `~/.inspr/secrets/agents/*.env` — load via env, **never cat / Read / display**

## Adding new doctrine

| Where it goes | What it is |
| --- | --- |
| `inspr-modules/docs/AGENTS-CORE.md` | Hard universal rules (every agent everywhere) |
| `inspr-modules/docs/AGENTS-PROFILE-MARKUS.md` | Markus's personal style / pacing preferences |
| `inspr-modules/docs/AGENTS-AGENT-<ROLE>.md` | Per-role overlays (SYSOP, PPM, DEV, …) |
| `<repo>/AGENTS.md` | Per-repo delta unique to that repo |

After upstream change, bump submodule in each consuming repo:

```sh
cd ~/Code/<repo>
git submodule update --remote doctrine
git commit doctrine -m "doctrine: bump to <short-sha>"
```

## How `/inspr` itself stays in sync

`/inspr.md` lives canonically in `inspr-modules/commands/inspr.md` and is symlinked into each consuming repo's `+agents/commands/` directory through the `./doctrine/` submodule. Edit it once upstream, bump the submodule, every repo gets the update.
