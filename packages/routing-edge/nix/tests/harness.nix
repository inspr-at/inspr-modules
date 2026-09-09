# Module-eval harness for the routing-edge NixOS module tests.
#
# `evalNixosModule` forces everything an operator would see (assertions,
# warnings, firewall, unit scripts and serviceConfig), so a configuration error
# surfaces as a failed assertion rather than hiding behind a lazy attribute that
# nobody evaluates.
#
# SPDX-License-Identifier: AGPL-3.0-only
{ lib, pkgs }:

let
  # Minimal stand-in for the NixOS option surface this module touches. It is a
  # convenience for fast focused runs, not a substitute for a real NixOS
  # evaluation — `nixos-eval.nix` covers that.
  stubNixosModule =
    { lib, ... }:
    {
      options = {
        systemd.services = lib.mkOption {
          type = lib.types.attrsOf lib.types.unspecified;
          default = { };
        };
        networking.firewall.allowedTCPPorts = lib.mkOption {
          type = lib.types.listOf lib.types.int;
          default = [ ];
        };
        environment.etc = lib.mkOption {
          type = lib.types.attrsOf lib.types.unspecified;
          default = { };
        };
        warnings = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        assertions = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                assertion = lib.mkOption { type = lib.types.bool; };
                message = lib.mkOption { type = lib.types.str; };
              };
            }
          );
          default = [ ];
        };
      };
    };

  evalNixosModule =
    {
      module,
      config ? { },
      extraArgs ? { },
    }:
    let
      evaluated = lib.evalModules {
        modules = [
          stubNixosModule
          module
          { inherit config; }
          { _module.args = { inherit pkgs; } // extraArgs; }
        ];
      };

      services = evaluated.config.systemd.services or { };

      observable = {
        warnings = evaluated.config.warnings;
        assertions = evaluated.config.assertions;
        firewall = evaluated.config.networking.firewall.allowedTCPPorts;
        # Only the generated document, never the whole option tree: forcing
        # `package`/`traefikPackage`/`contractFile` would throw for a disabled
        # configuration that legitimately never defines them.
        deployment = evaluated.config.services.inspr.routingEdge.generatedDeployment;
        fragment = evaluated.config.services.inspr.routingEdge.generatedFragmentFile;
        etc = evaluated.config.environment.etc;
        units = lib.mapAttrs (_: svc: {
          preStart = svc.preStart or null;
          script = svc.script or null;
          serviceConfig = svc.serviceConfig or { };
        }) services;
      };

      result = builtins.tryEval (builtins.deepSeq observable observable);
    in
    if result.success then
      {
        success = true;
        inherit (result.value)
          warnings
          assertions
          firewall
          units
          deployment
          fragment
          etc
          ;
        service = result.value.units."inspr-routing-edge" or null;
        failedAssertions = lib.filter (a: !a.assertion) result.value.assertions;
      }
    else
      {
        success = false;
        failedAssertions = [ ];
        warnings = [ ];
        assertions = [ ];
        firewall = [ ];
        units = { };
        service = null;
        deployment = { };
        fragment = null;
        etc = { };
      };

  # A test is a `{ name; assertion; }` pair. `assertion` is forced through
  # tryEval, which turns a `throw` (an option type rejecting a value, say) into a
  # reported failure. Other evaluation errors — a null dereference, for one —
  # tryEval cannot catch, so they still abort the run. That is the safe
  # direction: a regression is loud, never silently green.
  runTests =
    name: tests:
    let
      results = map (
        t:
        let
          forced = builtins.tryEval (t.assertion == true);
        in
        {
          inherit (t) name;
          passed = forced.success && forced.value;
        }
      ) tests;
      failed = lib.filter (t: !t.passed) results;
    in
    {
      inherit name results;
      total = lib.length tests;
      passed = lib.length tests - lib.length failed;
      failedTests = map (t: "[${name}] ${t.name}") failed;
    };
in
{
  inherit evalNixosModule runTests;
}
