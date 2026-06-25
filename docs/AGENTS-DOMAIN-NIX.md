# AGENTS — Domain: Nix

*Layer: `domain:nix` · INSPR-189 Phase 6 · Loaded on demand by `/nix`.*

Detailed rules for nix-darwin, Home Manager, devenv, NixOS modules, flakes, activation. Kernel (auto-loaded) has the irreversibles — most importantly **NEVER build NixOS configs on macOS** (build remotely via ssh; macOS HM CAN build locally). This pack adds technique depth.

**Load before**: editing any `.nix` file, running `nixos-rebuild`/`darwin-rebuild`/`home-manager switch`, designing a module, or debugging a flake eval/build failure.

---

## Hard rule: build location

- 🔴 **NEVER** run `nixos-rebuild` on macOS. From macOS, build remotely via ssh into the target host. macOS Home Manager (`darwin-rebuild`, `home-manager switch`) builds locally — that's fine.
- Identity / git config lives **declaratively** in nixcfg. No `git config --global` without confirming first; the canonical source is `programs.git.settings` under HM.
- To install or set up a package, edit nixcfg and rebuild — never `brew install` ad-hoc. When migrating from brew → nix, **uninstall the brew formula first** to avoid linking errors.

## Pattern: flakes & git-tracking

Flakes only see git-tracked files. Automation that generates files MUST `git add -N` (intent-to-add) BEFORE running flake operations:

```bash
git add -N path/to/new/file.nix
nix flake check
```

`builtins.readDir` patterns should warn or fail loudly when they discover zero files in a directory the user clearly intended to use.

## Pattern: module design

- 🟡 **Default to multi-user shapes** (`users.<name>.{trust,...}`) over single-user — costs nothing for the common case, prevents future breaking refactor.
- 🟡 **Build-time asserts against upstream drift**: any derivation that transforms an externally-versioned input MUST include sanity asserts — **positive markers** (expected content present) AND **inverse checks** (no old marker remaining). `pkgs.runCommand` is cheap insurance.
- 🟡 **Validation throws** must be on a guaranteed-evaluated path. Lazy-bound `let _ = X` doesn't count — use `builtins.seq` or `config.assertions`.
- 🟡 **Atelier mirrors**: prefer verbatim copy with a header note pointing at source until divergence is real. Only extract to `inspr-modules` with **≥2 consumers AND confirmed divergence pressure**. Bar for "common" = "every host MUST have this", NOT "every host I've inventoried has this".
- 🟡 **Module testability**: avoid `lib.mkMerge` in favor of direct `lib.listToAttrs` when tested via permissive stub typing. Ship module + tests + README in one PR/commit.

## Pattern: SSH client config in NixOS

NixOS `programs.ssh` client side does **NOT** include `/etc/ssh/ssh_config.d/*.conf`. For system-wide ssh-client `Match` blocks and `IdentityFile` pinning, always use `programs.ssh.extraConfig`. Verify the resolved client config with `ssh -v` after rebuild.

## Pattern: HM-on-NixOS

For HM-on-NixOS modules consuming flake inputs, always import upstream HM modules at the **NixOS-scope wire-up site**, never in HM-side files (unless `extraSpecialArgs` is wired). This keeps inputs captured at the right scope.

## Pattern: Nix syntax gotchas

- `or` keyword only works in `attrs.attr or default` form — NOT as a binary infix. Reach for explicit `if` over clever `or` when in doubt.
- Treat all text inside Nix `''` multiline strings as Nix tokens, including `#` comments. Prefer `pkgs.writeShellApplication` store paths to embedded heredocs to avoid `''${}` escaping pain.
- Avoid English-contraction apostrophes in awk/shell embedded in single-quoted strings (Nix-rendered or otherwise) — they prematurely terminate the quoted region.

## Workflow: NixOS rebuild safety

### Before `nixos-rebuild test/switch`

On a host you haven't recently rebooted, check for **staged-kernel state**. If pending, prefer `nixos-rebuild boot` + scheduled reboot over `switch` — switch with staged kernel risks subtle mismatches.

### Generic glibc binaries

For generic glibc binaries failing on NixOS with "no such file" on an existing executable, enable `programs.nix-ld` — fixes the whole class of binaries vs `steam-run`/`patchelf` for one.

### `mutableUsers` gotcha

With `users.mutableUsers = true` (default), `hashedPassword` is consumed only at INITIAL user creation. Subsequent rebuilds don't propagate. Use `hashedPasswordFile` instead. (NIX-79.)

### Don't kill an active rebuild

🔴 **Never** `systemctl stop nixos-rebuild-switch-to-configuration.service` on the "already loaded" error. Wait for `is-active inactive` or use `systemctl reset-failed`. Force-killing can leave partial activation state. (NIX-101.)

When automation seems stuck, investigate via `systemctl status` + `journalctl` BEFORE force-killing — operator-induced fix attempts often cause more damage than the original problem.

### Pulling on remote host before rebuild

When pulling on a remote host before `nixos-rebuild`, distinguish **flake-relevant** files (`.nix`, `flake.lock`, imports) from incidental files. Only the former block deployment.

## Workflow: activation script discipline

### Blast-radius check after activation failure

🔴 On HM/NixOS activation failure, verify: (a) login shell still execable, (b) PATH binaries present, (c) SSH still functional, (d) home-manager itself still in profile. Verify the file you came to change actually changed — early-step failure can silently bypass later steps.

🔴 Always run `nix profile list` on a macOS host BEFORE `home-manager switch` if there's any chance of imperative installs. Resolve conflicts FIRST to avoid bricked profile.

### Activation DAG hygiene

- **PATH is minimal** (coreutils only) in HM activation. Reference system tools by absolute path (`/usr/bin/awk`) or use bash builtins.
- **Reset umask at script start** — predecessors may have modified it. Restore prior umask before exiting if you mutated it.
- Treat all process-state mutables (`umask`, `cd`, `set -e`) as predecessors-may-have-touched. Reset at top.
- **Sequence install → wrap explicitly** with `entryAfter` when mixing package-manager binaries with Nix wrappers.
- **Immutable artifacts**: remove-then-recreate, not overwrite-in-place — locked file modes block subsequent rewrites.
- **Protective directories**: open with write perms first, do all writes, lock to restrictive mode last.

## Pattern: `etc/gitconfig` on NixOS

NixOS git build reads `/etc/gitconfig` by default. `environment.etc.gitconfig.text` works for system-wide `url.insteadOf` rewrites without needing `/root/.gitconfig`.

## Workflow: debugging confusing flake/module failures

- When `nix flake check` fails with confusing trace, **don't chase the trace at face value** — bisect by evaluating each top-level output category in isolation.
- When a module test fails opaquely, drop the harness and call `lib.evalModules` directly on a minimal stub to see the raw config tree. Splits module-vs-harness bugs.

## Pattern: per-host divergence & troubleshooting

- Per-host divergence is expected. Don't assume something on one machine exists on another without checking that host's nix config. Do NOT conflate `hosts/mba-mbp-work` (old Intel) with `hosts/mbp0` (new M5).
- When troubleshooting env issues, check whether the tool is **declared in nixcfg** before assuming imperative install. "Why isn't X working?" is often "not in this host's module set".

## Cross-cutting: paths & PII in shared docs

- 🟡 When a path is host-specific, NEVER hardcode it into shared-repo docs (even "obviously stale" ones). Unify via source-of-truth materialization first.
- No PII (family names, personal emails, phone numbers, MAC addresses) committed to nixcfg. MAC addresses live only in encrypted `.age` files.

---

*See also*: `/secrets` (agenix pipeline depth), `/ops` (fleet rebuild orchestration, SSH matrix), `/dev` (git-tracking aspects of flake eval). Full source: `AGENTS-CORE.md` topics `nix/*`, `nixos/*`.*
