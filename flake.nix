# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                  inspr-modules — public library flake                       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Reusable Home Manager modules + utilities from the INSPR initiative.
# Mission: "where your inspirations live" — democratize software dev by
# letting anyone consume the same primitives Markus uses on his own fleet.
#
# Pattern β graduation: this is the public library that "context flakes"
# (Markus's nixcfg, BYTEPOETS flake, family flake, future paid-product
# flakes) consume — so each context provides only its identity-specific
# values and gets the rest for free.
#
# Exports:
#   homeManagerModules.agent-secrets   Materialize agenix-encrypted env files
#                                       to a per-user "agent-exception" dir.
#   homeManagerModules.git-identity    Multi-identity git config with
#                                       gitdir + hasconfig:remote.*.url
#                                       includeIf rules.
#   homeManagerModules.paimos-config   Auto-bootstrap ~/.paimos/config.yaml
#                                       from materialized agent secrets.
#   homeManagerModules.ssh-authorized  Declarative ~/.ssh/authorized_keys
#                                       via aliased key map + trust list,
#                                       with marker-block coexistence.
#   homeManagerModules.default         Aggregate of all four above.
#   nixosModules.ssh-authorized        System-side counterpart to the HM
#                                       ssh-authorized — manages
#                                       users.users.<u>.openssh.authorizedKeys.keys
#                                       from the same keyring (multi-user,
#                                       status-filtered, force-toggleable).
#   nixosModules.default               Aggregate of all NixOS modules.
#   packages.<system>.secrets-audit    Bash script: detect drift between
#                                       secrets/*.age and secrets.nix
#                                       declarations.
#
# Consumer pattern (in your flake.nix):
#   inputs.inspr-modules.url = "github:markus-barta/inspr-modules";
#   inputs.inspr-modules.inputs.nixpkgs.follows = "nixpkgs";
#
#   home.imports = [
#     inputs.inspr-modules.homeManagerModules.git-identity
#     # ... or .default for all
#   ];
#
# License: MIT — deliberately permissive. This is a *library*; restrictive
# licenses on infrastructure modules would discourage exactly the adoption
# the mission depends on.
#
{
  description = "INSPR — reusable Home Manager modules and utilities (Pattern β public library)";

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
        };

        # ── Test suite (run via `nix flake check`) ───────────────────────
        # Each check is a derivation that succeeds (touches $out) if its
        # test passes, fails the build otherwise. Sandbox-friendly — no
        # network, all deps via nativeBuildInputs.
        checks =
          let
            secretsAuditPkg = pkgs.callPackage ./pkgs/secrets-audit { };

            # Run the module-eval suite at FLAKE-EVAL time (not at build
            # time). The suite's default.nix throws on failure, which
            # surfaces here as an eval error if `moduleEvalReport` is
            # forced. The runCommand below is just a thin wrapper that
            # records the report into $out so we have a tangible artifact.
            moduleEvalReport = import ./tests/module-eval {
              inherit pkgs;
              inherit (pkgs) lib;
            };
          in
          {
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

            # Module-eval tests (INSPR-72): exercise HM module options +
            # assertions + eval-time throws via lib.evalModules + a stub
            # HM harness. Catches regressions BEFORE `home-manager switch`
            # — assertions firing at the right times, REQUIRED options
            # staying required, deprecated options still warning, etc.
            #
            # The actual eval happens inside `moduleEvalReport` above
            # (forced at flake-eval time). This derivation just persists
            # the resulting summary report as a build artifact.
            module-eval = pkgs.runCommand "module-eval-tests" { } ''
              cat > $out <<'REPORT'
              ${moduleEvalReport}
              REPORT
            '';
          };
      }
    );
}
