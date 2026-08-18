# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/exports-importable.test.nix
#
# Every module the flake EXPORTS must be importable through the framework
# it is exported for. Driven by the flake's real `homeManagerModules` and
# `nixosModules` attrsets, so it cannot drift from what is advertised.
#
# Why this exists
# ───────────────
# `homeManagerModules.default` shipped in v0.4.0 AND v0.4.1 with a syntax
# error — a comment edit left a stray `imports = [` outside the module
# function. Nothing caught it: `nix flake check` does not force
# `homeManagerModules` (it is not a standard output; `nix flake show`
# reports it as `type`), and the per-module tests import individual files
# but never the aggregate. An outside reviewer found it by parsing every
# `.nix` file by hand. That is the coverage hole this closes: the public
# consumer path — the export attrset — is now the thing under test.
#
# What it asserts, per export
# ───────────────────────────
# The module evaluates with NO consumer configuration (all defaults). That
# proves: the file parses, it is a valid module, its options have valid
# defaults, and nothing throws when it is merely imported. It does not prove
# the module does anything useful — the per-module tests do that.
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:
let
  inherit (harness) evalModule evalNixosModule runTests homeManagerModules nixosModules;

  hmTests = lib.mapAttrsToList (name: path: {
    name = "homeManagerModules.${name} is importable with defaults";
    assertion = (evalModule { module = path; config = { }; }).success;
  }) homeManagerModules;

  nixosTests = lib.mapAttrsToList (name: path: {
    name = "nixosModules.${name} is importable with defaults";
    assertion = (evalNixosModule { module = path; config = { }; }).success;
  }) nixosModules;

  # If the flake passed nothing in, that is itself a wiring bug — say so
  # rather than silently running zero tests and reporting green.
  guard = [{
    name = "the flake actually handed its export attrsets to this suite";
    assertion = homeManagerModules != { } && nixosModules != { };
  }];
in
runTests "exports-importable" (guard ++ hmTests ++ nixosTests)
