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
#   inputs.inspr-modules.url = "github:inspr-at/inspr-modules/v0.4.4";  # pin a tag; main moves
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
        inspr-cli = ./modules/home-manager/inspr-cli.nix;
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
            workerDoctrineBundle = import ./lib/worker-doctrine-bundle.nix {
              inherit pkgs;
              skillSource = ./skills/inspr-worker-doctrine/SKILL.md;
              attributionSource = ./AGENTS.md;
              versioningSource = ./docs/AGENTS-VERSIONING.md;
            };

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
              # The suite imports EVERY exported module through the harness.
              # Driven by the real export attrsets, not a hand-kept list —
              # a hand-kept list is how "default imports all seven" drifted.
              inherit (self) homeManagerModules nixosModules;
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

            # The estate versioning policy is normative and linked from the
            # doctrine index. Keep its calendar grammar, real-date validation,
            # normalized ordering, gradual transition contract, and README
            # boundary executable (INSPR-320).
            calendar-version-doctrine = pkgs.runCommand "calendar-version-doctrine"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                  pkgs.python3
                ];
              }
              ''
                bash ${./tests/calendar-version-doctrine.sh} ${self}
                touch $out
              '';

            # Home Manager installs a harness-readable worker-doctrine bundle
            # whose references are byte-identical to the canonical attribution
            # mirror and calendar-version policy (INSPR-322). Exercise both the
            # positive bundle and deliberate mirror drift.
            worker-doctrine-surface = pkgs.runCommand "worker-doctrine-surface"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.gnugrep
                ];
              }
              ''
                bash ${./tests/worker-doctrine-surface.sh} ${self} ${workerDoctrineBundle}

                cp -R ${workerDoctrineBundle} ./drifted
                chmod -R u+w ./drifted
                printf '\nfixture drift\n' >> ./drifted/references/AGENTS.md
                if bash ${./tests/worker-doctrine-surface.sh} ${self} ./drifted; then
                  echo "worker-doctrine drift fixture unexpectedly passed" >&2
                  exit 1
                fi

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

            # Kernel-mirror freshness gate (INSPR-278). Editing the kernel
            # without re-mirroring AGENTS.md burned us in INSPR-269 (the 🔴
            # trust-contexts rule was invisible to non-Claude harnesses for
            # over a week). The mirror block carries a KERNEL-MIRROR-OF
            # sha256 attestation the re-mirror step must update; this check
            # recomputes the kernel hash and fails on mismatch — drift dies
            # at commit time, before it distributes to any consumer.
            kernel-mirror-stamp =
              pkgs.runCommand "kernel-mirror-stamp"
                {
                  nativeBuildInputs = [
                    pkgs.coreutils
                    pkgs.gnugrep
                    pkgs.gnused
                  ];
                }
                ''
                  kernel_hash="$(sha256sum ${./docs/AGENTS-KERNEL.md} | cut -d' ' -f1)"
                  stamp="$(grep -o 'KERNEL-MIRROR-OF: sha256:[0-9a-f]*' ${./AGENTS.md} | sed 's/.*sha256://')"
                  if [ -z "$stamp" ]; then
                    echo "AGENTS.md lacks the KERNEL-MIRROR-OF stamp" >&2
                    exit 1
                  fi
                  if [ "$stamp" != "$kernel_hash" ]; then
                    echo "kernel-mirror drift: docs/AGENTS-KERNEL.md sha256 ($kernel_hash) != AGENTS.md stamp ($stamp)." >&2
                    echo "Re-mirror the irreducible subset into AGENTS.md, then update the stamp (sha256sum docs/AGENTS-KERNEL.md)." >&2
                    exit 1
                  fi
                  touch $out
                '';

            # Ticket-first work attribution is an always-on global protocol
            # (INSPR-321), not an optional product-gauntlet convention. Keep
            # the kernel, non-Claude mirror, full reference and dispatcher in
            # lockstep and reject the retired opt-in wording.
            work-attribution-doctrine = pkgs.runCommand "work-attribution-doctrine"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.gnugrep
                ];
              }
              ''
                bash ${./tests/work-attribution-doctrine.sh} ${self}
                touch $out
              '';

            # inspr --help must tell the truth (INSPR-258): every dispatch
            # command appears and no stale NOT-YET-IMPLEMENTED claims remain.
            inspr-help-surface =
              let
                insprPkg = pkgs.callPackage ./pkgs/inspr { };
              in
              pkgs.runCommand "inspr-help-surface"
                { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
                  help="$(${insprPkg}/bin/inspr --help)"
                  for cmd in check heal onboard post-deploy; do
                    printf '%s' "$help" | grep -q "$cmd" || {
                      echo "inspr --help no longer mentions '$cmd'" >&2
                      exit 1
                    }
                  done
                  if printf '%s' "$help" | grep -qi "NOT YET IMPLEMENTED"; then
                    echo "stale NOT-YET-IMPLEMENTED claim in inspr --help" >&2
                    exit 1
                  fi
                  touch $out
                '';

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
          }
          # ── NixOS VM integration test (Linux only) ───────────────────────
          # Boots a server + client and proves sshd ADMITS trusted keys and
          # REJECTS untrusted/revoked ones. Needs a KVM builder with the
          # `nixos-test` system feature. On macOS the attribute does not
          # exist, so `nix flake check` there is unaffected. See
          # tests/nixos-vm/ssh-authorized.nix for what it proves and why.
          // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
            nixos-vm-ssh-authorized = import ./tests/nixos-vm/ssh-authorized.nix {
              inherit pkgs;
              sshAuthorizedModule = ./modules/nixos/ssh-authorized.nix;
            };
          }
          // {
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
