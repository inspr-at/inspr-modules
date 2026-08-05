# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                  inspr-modules — public library flake                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Reusable Home Manager modules + utilities from the INSPR initiative.
# Mission: "where your inspirations live" — democratize software dev by
# letting anyone consume the same primitives Markus uses on his own fleet.
#
# Atelier-pattern graduation: this is the shared atelier — the public
# library that "studios" (context flakes: Markus's nixcfg, family
# flake, family flake, future paid-product flakes) consume. Each studio
# provides only its identity-specific values; the rest comes from the
# atelier for free. See README.md "atelier pattern" for the full metaphor.
# (Older docs called this "Pattern β" — same architecture, opaque name.)
#
# Exports:
#   homeManagerModules.agent-secrets   Materialize agenix-encrypted env files
#                                       to a per-user "agent-exception" dir.
#   homeManagerModules.agent-skills    Declarative agent-skill provisioning
#                                       across CLI harnesses (Claude Code,
#                                       Codex, extensible). Bundled skills
#                                       ship under skills/<name>/.
#   homeManagerModules.git-atelier-credentials
#                                       Per-atelier outbound git credentials
#                                       (Strategy A deploy keys; B/C option-
#                                       typed). Forge-agnostic: github,
#                                       forgejo, codeberg, gitlab, gitea,
#                                       sourcehut, bare-SSH.
#   homeManagerModules.git-identity    Multi-identity git config with
#                                       gitdir + hasconfig:remote.*.url
#                                       includeIf rules.
#   homeManagerModules.paimos-config   Materialize Paimos instance routing
#                                       without credentials. Auth stays in the OS
#                                       keyring or process runtime environment.
#   homeManagerModules.ssh-authorized  Declarative ~/.ssh/authorized_keys
#                                       via aliased key map + trust list,
#                                       with marker-block coexistence.
#   homeManagerModules.default         Aggregate of all HM modules above.
#   nixosModules.ssh-authorized        System-side counterpart to the HM
#                                       ssh-authorized — manages
#                                       users.users.<u>.openssh.authorizedKeys.keys
#                                       from the same keyring (multi-user,
#                                       status-filtered, force-toggleable).
#   nixosModules.default               Aggregate of all NixOS modules.
#   packages.<system>.secrets-audit    Bash script: detect drift between
#                                       secrets/*.age and secrets.nix
#                                       declarations.
#   packages.<system>.inspr            Bash CLI: INSPR onboarding diagnostic +
#                                       heal + onboard sub-commands. Replaces
#                                       the older inspr-doctor.sh probe.
#
# Consumer pattern (in your flake.nix):
#   inputs.inspr-modules.url = "github:inspr-at/inspr-modules";
#   inputs.inspr-modules.inputs.nixpkgs.follows = "nixpkgs";
#
#   home.imports = [
#     inputs.inspr-modules.homeManagerModules.git-identity
#     # ... or .default for all
#   ];
#
# SPDX-License-Identifier: AGPL-3.0-only
# See LICENSE for the complete terms and the network-source obligation.
#
{
  description = "INSPR atelier — reusable Home Manager + NixOS modules and utilities (the public, shared mechanics layer)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    {
      # ── Home Manager modules ───────────────────────────────────────────
      # Each module is import-once; consumers add to their `imports = [ ... ]`
      # and configure via the `inspr.<name>.*` option namespace.
      homeManagerModules = {
        agent-secrets = ./modules/home-manager/agent-secrets.nix;
        agent-skills = ./modules/home-manager/agent-skills.nix;
        devenv-direnv-fix = ./modules/home-manager/devenv-direnv-fix.nix;
        git-atelier-credentials = ./modules/home-manager/git-atelier-credentials.nix;
        git-identity = ./modules/home-manager/git-identity.nix;
        paimos-config = ./modules/home-manager/paimos-config.nix;
        ssh-authorized = ./modules/home-manager/ssh-authorized.nix;
        default = ./modules/home-manager/default.nix;
      };

      # ── NixOS modules ──────────────────────────────────────────────────
      # System-side modules — same `inspr.<name>.*` option namespace as
      # the HM modules where applicable, but render into NixOS-native
      # option spots (e.g. `users.users.<u>.openssh.authorizedKeys.keys`).
      # Consumers import at NixOS-module scope (top-level
      # configuration.nix or shared profile).
      nixosModules = {
        ssh-authorized = ./modules/nixos/ssh-authorized.nix;
        default = ./modules/nixos/default.nix;
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        # ── CLI scripts as packages ──────────────────────────────────────
        packages = {
          secrets-audit = pkgs.callPackage ./pkgs/secrets-audit { };
          inspr = pkgs.callPackage ./pkgs/inspr { };
        };

        # ── Test suite (run via `nix flake check`) ───────────────────────
        # Each check is a derivation that succeeds (touches $out) if its
        # test passes, fails the build otherwise. Sandbox-friendly — no
        # network, all deps via nativeBuildInputs.
        checks =
          let
            secretsAuditPkg = pkgs.callPackage ./pkgs/secrets-audit { };

            # Module-eval suite results (INSPR-267). Evaluation is lazy —
            # nothing forces until the module-eval check derivation is
            # instantiated — and the suite never throws, so `nix flake
            # show` and check enumeration always work; a red unit test
            # fails as an ordinary check build below. Deliberately NOT
            # deduplicated across systems: per-system eval can genuinely
            # differ (e.g. the darwin-only stdenv recursion documented in
            # devenv-direnv-fix.test.nix), and deduping would mask
            # system-specific eval regressions.
            moduleEvalResults = import ./tests/module-eval {
              inherit pkgs;
              inherit (pkgs) lib;
            };
          in
          {
            # Repository licensing is part of the build contract: canonical
            # legal text, package metadata, source headers and public doctrine
            # must stay aligned on the exact SPDX identifier.
            license-surface = pkgs.runCommand "license-surface"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                ];
              }
              ''
                bash ${./tests/license-surface.sh} ${self}
                touch $out
              '';

            # Current repository and container references are operational
            # inputs. Keep them on the canonical INSPR organization while
            # preserving the intentionally personal nixcfg location.
            repository-location-surface = pkgs.runCommand "repository-location-surface"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                ];
              }
              ''
                bash ${./tests/repository-location-surface.sh} ${self}
                touch $out
              '';

            # Functional tests for the secrets-audit binary. Runs each
            # fixture (clean / declared-missing / orphan / with-comments)
            # through the binary and asserts exit codes + output content.
            # Includes a regression test for INSPR-50 (--help PATH leak).
            secrets-audit-functional = pkgs.runCommand "secrets-audit-functional"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                  pkgs.gnused
                  secretsAuditPkg
                ];
              }
              ''
                # Copy the tests dir into the sandbox (sources are read-only by default)
                cp -r ${./tests} ./tests
                chmod -R u+w ./tests
                cd ./tests/secrets-audit
                SECRETS_AUDIT=${secretsAuditPkg}/bin/secrets-audit \
                  bash ./run-tests.sh
                touch $out
              '';

            # Executes rendered paimos-config activations against synthetic
            # files. Covers fail-before-replace behavior, the legacy api_key
            # rollout guard, shell-safe diagnostics, and CR/LF/quote-safe URL
            # encoding without reading any real user configuration.
            paimos-config-functional = import ./tests/paimos-config-functional.nix {
              inherit pkgs;
            };

            # Executes the rendered ssh-authorized activation against
            # synthetic authorized_keys files (INSPR-261): fresh host,
            # valid-marker replacement preserving manual lines, missing
            # end marker fails loudly with the original untouched, and
            # substring-only markers never truncate.
            ssh-authorized-functional = import ./tests/ssh-authorized-functional.nix {
              inherit pkgs;
            };

            # Module-eval tests (INSPR-72): exercise HM module options +
            # assertions + eval-time throws via lib.evalModules + a stub
            # HM harness. Catches regressions BEFORE `home-manager switch`
            # — assertions firing at the right times, REQUIRED options
            # staying required, deprecated options still warning, etc.
            #
            # The eval happens when this derivation is instantiated; the
            # pass/fail decision happens when it is BUILT (INSPR-267):
            # report always lands in the build log, $out persists it on
            # success, and any failed sub-test exits non-zero — an
            # ordinary failed check, not a flake-eval error.
            module-eval = pkgs.runCommand "module-eval-tests"
              {
                report = moduleEvalResults.report;
                failedCount = toString (builtins.length moduleEvalResults.failedTests);
                passAsFile = [ "report" ];
              } ''
                cat "$reportPath"
                cp "$reportPath" $out
                if [ "$failedCount" != "0" ]; then
                  echo "module-eval: $failedCount sub-test(s) failed" >&2
                  exit 1
                fi
              '';
          };
      }
    );
}
