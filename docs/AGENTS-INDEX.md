# Layered Doctrine — Index

The kernel loads automatically; domain packs and role overlays load on demand.
Each consuming repository loads its own delta (`AGENTS.md` or a repository-specific overlay).

## Files

### Auto-loaded by CLAUDE.md (always-on)

| File | Scope tag | Loaded as | Description |
|---|---|---|---|
| **AGENTS-KERNEL.md** | `kernel` | `@./doctrine/docs/AGENTS-KERNEL.md` in every CLAUDE.md | universal hard-safety + identity + slash-command router. Budget ≤12 000 bytes (`wc -c`; enforced by `inspr check`) — see § "The budget is 12 000 BYTES" below. The only auto-loaded shared doctrine. |
| **`<repo>/AGENTS.md`** | `repo:*` | `@./AGENTS.md` in every CLAUDE.md | Per-repo delta for each consuming repository. |

### On-demand domain packs (loaded by slash commands)

| Pack | Loaded by | Description |
|---|---|---|
| AGENTS-DOMAIN-DEV.md | `/dev` | Git workflow depth, build/test gates, code style, dev tooling |
| AGENTS-DOMAIN-SECRETS.md | `/secrets`, `/incident` | agenix pipeline, env-file pattern, 1P CLI, secret-leak protocol |
| AGENTS-DOMAIN-NIX.md | `/nix` | nix-darwin, Home Manager, devenv, NixOS modules + activation |
| AGENTS-DOMAIN-OPS.md (private) | `/ops` | Fleet ops, SSH matrix, infra, tailscale, fleet-state |
| AGENTS-DOMAIN-PPM.md (private) | `/ppm` | Paimos/Aeon CLI, ticket conventions, project landscape, API endpoints. Retired personal-tracker hostnames live only in the private pack (INSPR-483); the classic CLI remains for instances that have not moved. |
| AGENTS-DOMAIN-IAC.md (private) | `/iac` | L5 service config (Terraform for Zitadel, Cloudflare, GitHub and Headscale in the operator's infrastructure repository) |

### On-demand reference / role overlays

| File | Loaded by | Description |
|---|---|---|
| AGENTS-CORE.md | direct read | Exhaustive universal reference; the kernel and domain packs cover the daily workflow. |
| AGENTS-AGENT-DEV.md | `/dev` | Development role overlay. |
| Operator profile (private) | `/style` | Operator preferences beyond the shared doctrine. |
| Operations and planning role overlays (private) | relevant private commands | Roles with operator-specific scope. |
| `<repo>/AGENTS.md` or a repository-specific overlay | per-repo loader | Consumer delta, maintained by that repository. |

### Normative cross-domain references

| File | Applies when | Description |
|---|---|---|
| [AGENTS-VERSIONING.md](AGENTS-VERSIONING.md) | Creating, publishing, consuming, comparing, pinning, deploying, or migrating any version-bearing artifact | INSPR Calendar Versioning 3 (`inspr-calver-3`, label `INSPR-CalVer3`; `YYMMDDhhmmss.0.0`, SemVer-syntactic and fixed-width sortable; CalVer2 `inspr-calendar-v2` shares the coordinate and stays valid history; v1 `YY.MM.DD[.hh.mm.ss]` superseded), the six-segment shared Pretty presentation, legacy display weights (data: `lib/calendar-version-display.json`), gradual per-repository adoption, mixed-era behavior, supply-chain gates, ecosystem exceptions, and the value-free estate inventory. |

## Repository architecture — the atelier pattern

**Read this before drawing any conclusion about a repository's visibility.**

INSPR repositories come in two kinds, and confusing them produces confident,
wrong recommendations:

| Kind | What it is | Visibility | Examples |
|---|---|---|---|
| **Atelier** | A shared **library** of identity-free primitives, published so anyone can consume the same building blocks the fleet uses | **public by design** | `inspr-modules` |
| **Studio** | A **context flake** supplying identity-specific values — hosts, keys, instances, preferences — on top of an atelier | private | an operator's host configuration, a family flake, future product flakes |

The atelier's own `flake.nix` states the mission: *"democratize software dev by
letting anyone consume the same primitives that run a real fleet."* Its
modules are built to match — `ssh-authorized` takes a key map as a parameter,
`git-identity` takes identities, and `paimos-config` is documented as
materialising instance routing **without credentials**.

### The failure this prevents

🔴 **Public content in an atelier is the design, not a leak.**

The trust-contexts rule — classify by ownership of the output, personal / INSPR /
business, never by GitHub org — is about *where work belongs*. It says
nothing about libraries, and applied alone it misclassifies an atelier: a public
repository holding fleet-shaped material reads as an accident when it is the
stated purpose.

### The rule

- 🟡 **Before concluding anything about a repository's visibility, read its
  `flake.nix` header and `README.md`.** An atelier says what it is in the first
  three lines.
- 🟡 **An atelier must stay identity-free.** Content that cannot be parameterised
  — a fleet SSH matrix, an instance routing table, one person's working
  preferences — does not belong in one, whatever the repository's visibility.
- 🟡 **The correct fix for operator content in an atelier is to move the
  content, never to change the repository's visibility.** The library is
  load-bearing for consumers who are not you.

## Worktree placement

🟡 **Agent worktrees go in `.claude/worktrees/<slug>/` inside the repository.**

That path is already gitignored in wired repos, it travels with the checkout, it
is visible to anyone working there, and it cannot be mistaken for a sibling
repository in a file browser.

### Companion rules

- 🟡 **Two agents in one checkout will collide silently.** A `git checkout` moves
  the ground under the other; a `git add -A` sweeps up work in flight that was
  never yours. If two things are being worked on, that is two worktrees — and the
  coordinating agent is one of the two, not an exception to its own rule.
- 🟡 **Announce before acting in a tree you do not own.** One message, and it has
  prevented at least two collisions in a single day.
- 🟡 **Return the shared checkout to its default branch when you are done.** A
  tree left on a deleted branch costs the next session a confusing `git pull`
  failure. Cheap for you, expensive for them.
- 🟡 **`git worktree prune` after any run that used a temporary directory.** It
  removes only registrations whose directory is already gone, so it cannot touch
  live work.

## Where the operator packs went

This repository is a **public library flake** — see the atelier section above.
The operator-specific doctrine packs no longer live here, because a fleet SSH
matrix, an instance routing table and one person's working preferences have no
identity-free form and had no business in an atelier.

They are in a private doctrine repository the operator owns, vendored by studio
repositories as a second submodule at `doctrine-private/` over SSH:

| Moved | Loaded by |
|---|---|
| the operator profile | `/style` |
| `AGENTS-DOMAIN-PPM.md` | `/ppm` |
| `AGENTS-DOMAIN-OPS.md` | `/ops`, `/incident` |
| `AGENTS-DOMAIN-IAC.md` | `/iac` |
| `AGENTS-AGENT-<ROLE>.md` (operator roles) | role overlays, loaded by the operator's slash commands |

**The commands still work.** `/ppm`, `/ops`, `/iac`, `/style` and `/incident`
are unchanged from a consumer's point of view — they resolve through
`doctrine-private/commands/` instead of `doctrine/commands/`. A repository that
vendors only the public half simply does not have them, which is the intent:
`janus`, `paimos` and `pharos` get a baseline an outside contributor can act on.

`/incident` is deliberately **split** — it loads `DOMAIN-OPS` from the private
half and `DOMAIN-SECRETS` from this one, because the secrets pack is mostly
generic principles.

Staying here: `AGENTS-KERNEL`, `AGENTS-CORE`, `AGENTS-DOMAIN-{DEV,NIX,SECRETS}`,
`AGENTS-AGENT-DEV`, this index, and every Nix module, package and bundled skill.

## Kernel gatekeeper & size budget

**The kernel grows ONLY for**:

1. A new safety irreversible (would prevent immediate damage in turn 1)
2. A new global protocol change affecting every agent in every repo
3. A new slash command (router update)

Everything else — domain knowledge, role-specific rules, technique notes, style preferences — goes to a **domain pack**. Don't add a rule to the kernel that could live elsewhere. Default to a domain pack; promote to kernel only when the cost of NOT having it always-loaded exceeds the auto-load cost. When the kernel is near budget, prefer **merging into an adjacent bullet** over adding a new one.

### The budget is 12 000 BYTES

Measure with `wc -c`, not a character count — the 🔴/🟡 emoji are multibyte, so the two differ by ~130. Enforced by `inspr check` → `check_doctrine_kernel_size_budget` (`pkgs/inspr/inspr.sh`), which reads `$NIXCFG_DIR/doctrine/docs/AGENTS-KERNEL.md`.

## Layer-file format conventions

- Topics within a layer follow a LOGICAL order: security → incident-response → secrets → style → tools → process → workflow → pacing → git → nix/nixos → infra → agent-identity → other (alphabetical tail).
- Within each topic, rules sort by priority: 🔴 HARD → 🟡 STRONG → 🟢 SOFT.
- Extraction provenance and contributing source mappings are kept in the operator's private doctrine.

## Migration and audit record

The migration and audit record is kept in the maintainer's private archive.
