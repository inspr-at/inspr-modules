# Changelog

All notable changes to **inspr-modules** are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed

- **Kernel budget audit — 9 997 → 7 334 bytes, no rule lost.** Every rule in the old kernel is either still present or already existed verbatim in the pack it was demoted to (verified mechanically before removal). Highlights: **5 of 9 router size estimates were wrong**, all understating — `/style` claimed 20k but loads 46k, `/incident` claimed 5k but loads 20k, `/ppm` 8k → 22k, `/ops` 12k → 18k, `/dev` 8k → 11k; the per-row column was replaced with one accurate "heavy ones" line. **6 🟡 rules that violated the kernel's own "turn-1 irreversibles only" gatekeeper were removed** — `gh pr view/diff`, push-is-normal-flow, multi-agent stash, `git config --global` (all already in `/dev`) and the PPM keyring paragraph (`/ppm` covers it in more depth); `zellij, NOT tmux` lived only in the 46k `PROFILE-MARKUS`, so it moved to `/dev` instead of being dropped. **~20 % of the kernel described the kernel** — gatekeeper rule, cross-reference footer and per-repo-deltas paragraph moved to `AGENTS-INDEX.md`; the purpose statement appeared three times and the secret-read ban twice, both deduplicated. **Budget reconciled**: the header claimed `≤ 10 000 chars` while the only enforcement (`inspr check`) was `12 000` **bytes** — now one number, one unit, with the multibyte-emoji trap documented. Stale scope fixed: the header listed consumers as "nixcfg, inspr, fleetcom, inspr-modules", omitting `ops` and naming `fleetcom`, which the kernel body declares archived. Headroom restored from 3 bytes to 4 666.

- **Kernel: trust contexts are now always-on doctrine** — the `Umbrella` bullet in `docs/AGENTS-KERNEL.md` became `Umbrella & trust contexts`. Every repo is exactly one of **personal** (Markus's own infra + hobby projects), **INSPR** (the FOSS project, org `inspr-at`), or **augmentoring** (INSPR's business side — commercial/client work, e.g. `dsccfg`). Classification follows **ownership of the output**, explicitly **not** the GitHub org, because the orgs do not match the split: no `augmentoring` org exists yet, `amt-com` and `dsccfg` still sit under `markus-barta/`, and 5 of 9 `inspr-at` repos are private. Carries one hard rule — 🔴 never cross contexts with credentials or tickets (`dsccfg` → `DSC26`, personal fleet → `OPS`); STOP and ask. Promoted to kernel rather than a domain pack because cross-context credential leakage is a turn-1 irreversible and the rule must reach agents in *every* repo, including ones that never load `/ops`. Full classification table and migration plan live in the INSPR PPM guideline `trust-contexts`. ⚠️ **The kernel is now at 9 997 / 10 000 chars — 3 chars of headroom.** The next addition must trim something first; merging into an adjacent bullet (as done here) is the pattern that fits. Decided 2026-07-26.
- **Repository license is now AGPL-3.0-only** - canonical legal text, Nix
  package metadata, module headers, public documentation and licensing doctrine
  now share one exact identifier. Existing grants on earlier revisions remain
  valid; the new license boundary begins with INSPR-236.
- **`homeManagerModules.paimos-config` now manages routing only** — generated `~/.paimos/config.yaml` contains `default_instance` and instance URLs, never `api_key`. Existing literal `url` and `urlEnvFile` + `urlVar` routing sources remain supported; runtime URLs are encoded through an explicit jq store path so quotes, CR/LF, backslashes, and control characters cannot corrupt YAML. Missing/empty routing input fails before the atomic move and preserves the prior config. INSPR workstations authenticate interactively with `paimos auth login` into the OS keyring; headless automation injects `PAIMOS_URL` + `PAIMOS_API_KEY` into the process from approved encrypted storage. The old `apiKeyEnvFile` and `apiKeyVar` options remain accepted for one compatibility release but are ignored and emit an evaluation warning—this is evaluation-only compatibility, not credential migration. A non-printing structural guard refuses to replace an existing legacy `api_key` config until `paimos auth whoami` runs with all auth overrides unset and performs the Paimos 4.8 migration. Migration must happen before any new interactive login so the old inline credential cannot overwrite a newly entered keyring credential. Structural and executable regressions prove nested YAML, fail-before-replace behavior, shell-safe diagnostics, legacy-config preservation, and absence of configured credential-file/variable markers from activation. [INSPR-225]

### Added

- **`nixosModules.ssh-authorized`** — System-side counterpart to the HM `ssh-authorized` module. Same shared keyring (rich-key form with `status: active | legacy | revoked`) but renders into `users.users.<u>.openssh.authorizedKeys.keys` (which NixOS materializes as `/etc/ssh/authorized_keys.d/<u>` per the default `AuthorizedKeysFile` directive). **Multi-user**: `inspr.ssh.authorized.users.<name>.{trust, force, extraKeys}` — each user gets its own trust subset, `force` toggle (wraps the rendered list in `lib.mkForce` to displace upstream-injected keys, e.g. server-home / hokage profiles; default `false` merges via list concatenation), and `extraKeys` escape hatch for one-off raw keys that don't belong in the shared keyring. Throws at eval time on undeclared alias OR revoked-in-trust (same footgun guards as the HM module). 14 module-eval sub-tests cover disabled shape, empty-users warning, sorted-output determinism, undeclared/revoked throws, mixed string+rich keyring, multi-user rendering, force=true override, force=false merge, and extraKeys append. **Unblocks INSPR-76 RSA retirement** — flipping `status = "legacy"` → `"revoked"` in the shared keyring is now sufficient to retire across the whole fleet (no more hand-editing each host's `users.users.<u>.openssh.authorizedKeys.keys` literal). Best practice: define the keyring once in a plain-Nix file imported BOTH at NixOS-module scope (for this module) AND at HM scope (for the HM module). [INSPR-73]
- **`nixosModules.default`** — Aggregate of all NixOS modules. Convenience for consumers wanting "all of INSPR system-side" in one import.
- **NixOS-shaped test harness** — `evalNixosModule` in `tests/module-eval/harness.nix`, mirror of the existing `evalModule` (HM-shaped) but with a stub NixOS option-set covering `users.users.<u>.openssh.authorizedKeys.keys`, `warnings`, and `assertions`. Lets us exercise NixOS modules at flake-eval time without a real NixOS evaluation. Total module-eval sub-tests: 33 → 47.

- **`homeManagerModules.ssh-authorized`** — Declarative `~/.ssh/authorized_keys` management via aliased key map + trust list. Consumer declares `keys = { "alias" = "ssh-... comment"; }` and `trust = [ "alias-1" "alias-2" ]`; module renders a marker-delimited block in `~/.ssh/authorized_keys`. **Co-existence guarantee**: only the marker block is managed; lines outside it (Headscale deploy keys, GitHub Actions OIDC, recovery keys) are preserved across activations. Activation script writes the file directly (mode 0600) instead of symlinking from `/nix/store`, so OpenSSH `StrictModes` is satisfied. Trust list sorted at eval time → byte-identical output regardless of input order (no spurious git noise on rebuilds). Throws at eval time if `trust` references an alias not in `keys` (silent fall-through would be an audit-defeating footgun — sshd silently ignores empty-body lines). [INSPR-43]
- **`ssh-authorized` rich keys form** — `keys` now accepts EITHER a bare string (simple form, unchanged) OR a `{ key; status?; note?; }` submodule for grandfathering / audit. `status = "active"` (default) renders as before; `status = "legacy"` adds a `[legacy]` tag to the comment line for fleet-wide visibility (so a future inspr-doctor / FleetCom dashboard can inventory pending retirements); `status = "revoked"` is NOT admitted to authorized_keys but the declaration stays in `keys` as a historical audit record — and **throws at eval time if a revoked alias is also in `trust`** (catches the "I forgot to remove from trust" footgun). Optional `note` field appends ` (<note>)` to the comment line on any non-throwing status. Both forms accepted in the same map. 4 additional module-eval sub-tests cover legacy tagging, mixed string+rich keys, revoked-in-trust throw, and revoked-not-in-trust declaration preservation. [INSPR-77, prereq for INSPR-76 retirement workflow]
- **Module-eval test suite** — `flake.checks.<system>.module-eval` runs 33 sub-tests across the four HM modules via `lib.evalModules` + a stub HM harness (`tests/module-eval/harness.nix`). Catches regressions BEFORE `home-manager switch`: assertions firing at the right times, REQUIRED options staying required, eval-time throws still throwing, deprecated options still warning, `programs.git.includes` count for git-identity contexts, etc. Sandbox-friendly, runs on every `nix flake check`. [INSPR-72]

### Fixed

- **`paimos-config` is now independently consumable** — previously referenced `config.inspr.secrets.agents.enable` directly, which failed eval (`attribute 'secrets' missing`) when `paimos-config` was imported without `agent-secrets`. Now uses `config.inspr.secrets.agents.enable or false` — modules can be picked à la carte. (Found by INSPR-72 module-eval suite — the kind of regression module-level eval catches that integration tests miss.)

### Planned

- **NixOS VM integration tests** — `pkgs.testers.runNixOSTest` for end-to-end activation testing. Heavy but the gold standard.
- **More NixOS-equivalent modules** — server-side counterparts for the remaining HM modules (`agent-secrets`, `paimos-config`, `git-identity`). `ssh-authorized` shipped above as the first NixOS module (INSPR-73). [INSPR-24 Stage 4]
- **`ssh-authorized` keyring layout** — file-per-key under `keys/<alias>.pub` for fleet-scale (~10+ keys); current inline form stays supported. [INSPR-74]
- **`ssh-authorized` build-time validation** — pipe each key through `ssh-keygen -l` (or a regex) at eval to catch typos before activation. [INSPR-75]
- **1Password tag-export integration** — Phase 2 secrets graduation (consumer-side script that materializes `.age` files from tagged 1Password items). [INSPR-23]
- **Doctor genericization** — extract Markus-specific values from `inspr-doctor` into config so the same script runs against any consumer's setup. [INSPR-44 follow-up]

---

## [0.1.0] — 2026-05-02

Initial Pattern β extraction from [markus-barta/nixcfg](https://github.com/markus-barta/nixcfg).

### Added

- **`homeManagerModules.agent-secrets`** — Materialize agenix-encrypted env files into a per-user "agent-exception" directory at HM activation. Universal contract; consumer provides `encryptedRoot` (path), and the module handles discovery + decryption + lock-after-activation.
- **`homeManagerModules.git-identity`** — Multi-identity git config with `gitdir:` AND `hasconfig:remote.*.url:` includeIf rules. Consumer declares `identities` (named) and `contexts` (per-context overrides, by either gitdir or remote URL pattern). The repo's own remote URL picks the identity automatically.
- **`homeManagerModules.paimos-config`** — Auto-bootstrap `~/.paimos/config.yaml` from agent-secrets-materialized API key files. Consumer declares `instances` (named) and `defaultInstance`.
- **`homeManagerModules.default`** — Aggregate of all three above; convenience for consumers wanting "all of INSPR" in one import.
- **`packages.<system>.secrets-audit`** — Nix-derivation-packaged bash script that detects drift between `secrets/*.age` files and their declarations in `secrets/secrets.nix`. Three modes: human report, `--quiet`, `--json`.

### Fixed (during initial extraction + day-of audit pass)

- **`agent-secrets.encryptedRoot` is REQUIRED** — was a misleading default (`../../secrets/agents` relative to the module file, which broke immediately on consumers whose layout differed). Now consumers must declare it explicitly. Loud failure beats silent emptiness. (commit `fd001ce`)
- **Activation security regression** — `agent-secrets` now uses `trap chmod 0500 EXIT` to GUARANTEE the decrypted dir is relocked on ANY activation exit path, not just the happy path. Without this, a mid-decrypt failure would leave the dir at 0700 (writable) until next successful activation. (closes audit finding H4)
- **YAML injection vector** — `paimos-config` api_key values are now written as YAML single-quoted scalars with proper `'` → `''` escaping. Previously written unquoted, which would break parsing on values containing leading `*`/`&`/`[`/`{` or embedded `:` `#`. (closes audit finding H1)
- **Eval-time assertions** — `paimos-config` now asserts `defaultInstance ∈ instances` AND `instances ≠ {}` at switch time. Misconfig fails loudly, not silently at paimos CLI runtime. (closes audit findings H3 + O6)
- **Tmpfile cleanup** — `paimos-config` activation now uses `trap rm -f EXIT` to clean up the YAML tmpfile on any failure. No more dotfile garbage in `~/.paimos/`. (closes audit finding H2)
- **Hostname silent-default footgun** — `agent-secrets` now throws a clear eval-time error if hostname can't be determined (was: literal string `"$(hostname -s)"` which silently produced zero host-specific secret discovery). New explicit `hostname` option as alternate path. (closes audit finding C8)
- **`secrets-audit` packaging** — switched from `mkDerivation + postFixup-sed-injection` to `writeShellApplication`. The previous form broke `--help` (the PATH-export sed injection collided with the help-extraction sed). Now `--help` is clean; closure is automatic-minimum; shellcheck runs at build time. (closes audit findings C7 + H6 + M2 + O4)

- **Functional test suite** — `flake.checks.<system>.secrets-audit-functional` runs 7 sub-tests: drift detection across 4 fixtures (clean / declared-missing / orphan / commented-out) plus a `--help` regression test for INSPR-50/C7. Sandbox-friendly, runs on every `nix flake check` + every CI push. (closes audit finding O1, partial — module-eval tests deferred to INSPR-72)

- **GitHub Actions CI** — `.github/workflows/check.yml` runs `nix flake check --all-systems` on push + PR + manual trigger; cross-builds `secrets-audit` on Ubuntu + macOS; includes a regression test that `--help` doesn't leak the PATH export. (closes audit finding O2)

### Documentation

- **CHANGELOG.md** (this file) — keepachangelog.com format. (closes audit finding O3)
- **README** — added "Testing" section (how to run + roadmap), "Versioning + deprecation policy" section (semver interpretation + 1-MINOR-cycle deprecation window), "Recovery scenarios" table (9 common failure modes + fixes). (closes audit findings O5 + O7)
- **All module headers + option descriptions** stripped of Markus-specific identifiers, paths, and roadmap details. Public-library-appropriate framing throughout. (closes audit findings C1 + C2 + C3 + C4 + C6)

### Changed

- **`paimos-config.instances` default is `{}`** (was `ppm = { ... }` Markus-specific). Consumers MUST declare their own instances; no sensible cross-context default for a public library.
- **`git-identity` accepts `identities` + `contexts` as options** (was hardcoded Markus-personal + former-work values). Universal mechanics; per-consumer values.
- **All module documentation** — stripped Markus-specific identifiers, paths, and roadmap details from module source. Public-library-appropriate framing throughout.

### Provenance

Extracted from the INSPR onboarding sessions of 2026-05-01 and 2026-05-02:
- Day 1: M5 (mbp0) onboarded; agent-secrets + git-identity patterns established
- Day 2 morning: paimos-config added; inspr-doctor v2 (host-class profiles) shipped
- Day 2 afternoon: Pattern β extraction (this v0.1.0); audit pass + 18 fixes

See the (private) [inspr](https://github.com/markus-barta/inspr) umbrella repo for the narrative playbook.
