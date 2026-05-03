# Changelog

All notable changes to **inspr-modules** are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- **`homeManagerModules.ssh-authorized`** — Declarative `~/.ssh/authorized_keys` management via aliased key map + trust list. Consumer declares `keys = { "alias" = "ssh-... comment"; }` and `trust = [ "alias-1" "alias-2" ]`; module renders a marker-delimited block in `~/.ssh/authorized_keys`. **Co-existence guarantee**: only the marker block is managed; lines outside it (Headscale deploy keys, GitHub Actions OIDC, recovery keys) are preserved across activations. Activation script writes the file directly (mode 0600) instead of symlinking from `/nix/store`, so OpenSSH `StrictModes` is satisfied. Trust list sorted at eval time → byte-identical output regardless of input order (no spurious git noise on rebuilds). Throws at eval time if `trust` references an alias not in `keys` (silent fall-through would be an audit-defeating footgun — sshd silently ignores empty-body lines). 8 module-eval sub-tests cover the option surface, throw paths, determinism, custom markers, and the empty-trust warning. [INSPR-43]
- **Module-eval test suite** — `flake.checks.<system>.module-eval` runs 29 sub-tests across the four HM modules via `lib.evalModules` + a stub HM harness (`tests/module-eval/harness.nix`). Catches regressions BEFORE `home-manager switch`: assertions firing at the right times, REQUIRED options staying required, eval-time throws still throwing, deprecated options still warning, `programs.git.includes` count for git-identity contexts, etc. Sandbox-friendly, runs on every `nix flake check`. [INSPR-72]

### Fixed

- **`paimos-config` is now independently consumable** — previously referenced `config.inspr.secrets.agents.enable` directly, which failed eval (`attribute 'secrets' missing`) when `paimos-config` was imported without `agent-secrets`. Now uses `config.inspr.secrets.agents.enable or false` — modules can be picked à la carte. (Found by INSPR-72 module-eval suite — the kind of regression module-level eval catches that integration tests miss.)

### Planned

- **NixOS VM integration tests** — `pkgs.testers.runNixOSTest` for end-to-end activation testing. Heavy but the gold standard.
- **NixOS-equivalent modules** — server-side counterparts for the HM modules currently here (workstation-only). [INSPR-24 Stage 4 + INSPR-73]
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
- **`git-identity` accepts `identities` + `contexts` as options** (was hardcoded Markus-personal + BYTEPOETS values). Universal mechanics; per-consumer values.
- **All module documentation** — stripped Markus-specific identifiers, paths, and roadmap details from module source. Public-library-appropriate framing throughout.

### Provenance

Extracted from the INSPR onboarding sessions of 2026-05-01 and 2026-05-02:
- Day 1: M5 (mba-mbp-m5-work) onboarded; agent-secrets + git-identity patterns established
- Day 2 morning: paimos-config added; inspr-doctor v2 (host-class profiles) shipped
- Day 2 afternoon: Pattern β extraction (this v0.1.0); audit pass + 18 fixes

See the (private) [inspr](https://github.com/markus-barta/inspr) umbrella repo for the narrative playbook.
