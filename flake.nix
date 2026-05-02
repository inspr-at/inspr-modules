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
#   homeManagerModules.default         Aggregate of all three above.
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
        default = ./modules/home-manager/default.nix;
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
      }
    );
}
