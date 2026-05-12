# ─────────────────────────────────────────────────────────────────────────
# inspr-modules/tests/module-eval/harness.nix
#
# Stub Home Manager harness for module-eval testing via `lib.evalModules`.
#
# Why this exists
# ───────────────
# Functional tests (tests/secrets-audit/) catch binary-level regressions.
# Module-eval tests catch eval-time regressions BEFORE `home-manager switch`
# even runs:
#   - assertions fire when they should (paimos-config)
#   - throws fire when they should (agent-secrets undefined hostname,
#     git-identity unknown identity reference)
#   - defaults are sane (decryptedDir derives from homeDirectory, etc.)
#   - the option type system rejects malformed inputs
#
# Without this, a refactor that silently drops an assertion or a throw is
# only caught downstream — at consumer-side `home-manager switch` time, by
# whichever consumer happens to have the misconfiguration that would have
# tripped the assertion. This harness pulls that detection one layer up.
#
# What it stubs
# ─────────────
# Home Manager injects three things our modules consume that don't exist
# in raw `lib.evalModules`:
#   1. `lib.hm.dag.entryAfter` (used to schedule activation scripts)
#   2. `home.*` options (homeDirectory, activation, packages)
#   3. `programs.*`, `warnings`, `assertions` options
#
# We provide minimal stubs for all three. The stubs are structural only —
# we don't validate that activation strings parse as bash, or that
# programs.git.includes are well-formed. That's HM's job. Our job is:
# does evaluation succeed/fail at the right times?
#
# Scope (intentional)
# ───────────────────
# OPTION layer + ASSERTION layer + EVAL-TIME-THROWS only.
# We do NOT exercise the activation scripts themselves — that requires a
# real HM environment + an `age` binary + recipient keys, which is the
# domain of NixOS VM tests (future INSPR-73).
#
# Public API
# ──────────
#   evalModule { module = ./path.nix; config = { ... }; }
#       → { success = true;  config; assertions; warnings; failedAssertions; }
#       → { success = false; }                  (eval threw)
#
#   runTests name [ { name = "..."; assertion = bool; } ... ]
#       → { name; total; passed; failedTests = [string]; }
#
# License: MIT (part of inspr-modules — see flake.nix).
# ─────────────────────────────────────────────────────────────────────────
{ lib, pkgs }:

let
  # ── lib.hm stubs ────────────────────────────────────────────────────────
  # HM modules call `lib.hm.dag.entryAfter [ deps ] data` to declare
  # ordering for activation scripts. We don't need real ordering — the
  # tests don't run activations. We just need the call to return a value
  # that survives the type check on `home.activation.<name>`.
  hmLib = {
    dag = {
      entryAfter   = deps: data: { inherit data; after = deps; };
      entryBefore  = deps: data: { inherit data; before = deps; };
      entryBetween = before: after: data: { inherit data before after; };
      entryAnywhere = data: { inherit data; };
    };
  };

  libWithHm = lib // { hm = hmLib; };

  # ── HM option-set stub ──────────────────────────────────────────────────
  # Mirrors the HM options our modules write into. All values are
  # `unspecified`-typed so we accept whatever the modules produce — we're
  # testing the modules, not HM's option machinery.
  stubHmModule = { lib, ... }: {
    options = {
      home = {
        homeDirectory = lib.mkOption {
          type    = lib.types.str;
          default = "/home/test-user";
        };
        activation = lib.mkOption {
          type    = lib.types.attrsOf lib.types.unspecified;
          default = { };
        };
        packages = lib.mkOption {
          type    = lib.types.listOf lib.types.unspecified;
          default = [ ];
        };
        # `home.file` for modules that render dotfile content via HM
        # (e.g., inspr.git.atelier.<name> writes known_hosts.d/inspr-*).
        # Stub-level type is unspecified — we don't validate that the
        # values are well-formed `home.file` entries, only that the path
        # mapping is rendered as expected.
        file = lib.mkOption {
          type    = lib.types.attrsOf lib.types.unspecified;
          default = { };
        };
      };
      programs = lib.mkOption {
        type    = lib.types.attrsOf lib.types.unspecified;
        default = { };
      };
      warnings = lib.mkOption {
        type    = lib.types.listOf lib.types.str;
        default = [ ];
      };
      assertions = lib.mkOption {
        type    = lib.types.listOf (lib.types.submodule {
          options = {
            assertion = lib.mkOption { type = lib.types.bool; };
            message   = lib.mkOption { type = lib.types.str;  };
          };
        });
        default = [ ];
      };
    };
  };

  # ── Eval helper ─────────────────────────────────────────────────────────
  # Force the parts that matter for module-eval testing (assertions,
  # warnings, activation scripts, programs.*) so that lazy throws inside
  # them surface as eval failures rather than silently passing.
  #
  # `tryEval` only catches throws — it returns { success = false; } with
  # NO error message (Nix limitation, see NixOS/nix#2176). For tests where
  # we need the message, callers can drop tryEval and let the throw bubble
  # up naturally; the test framework will surface it as a Nix error.
  evalModule = { module, config ? { }, extraArgs ? { } }:
    let
      evaluated = lib.evalModules {
        modules = [
          stubHmModule
          module
          { inherit config; }
          { _module.args = { inherit pkgs; hostname = null; } // extraArgs; }
        ];
        # Override `lib` so that modules calling `lib.hm.dag.entryAfter`
        # see our stubbed version.
        specialArgs = { lib = libWithHm; };
      };

      # Force the testable surface deeply enough that lazy throws fire.
      forced = builtins.deepSeq {
        inherit (evaluated.config) home programs warnings assertions;
      } evaluated;

      result = builtins.tryEval forced;
    in
      if result.success
      then {
        success    = true;
        config     = evaluated.config;
        assertions = evaluated.config.assertions;
        warnings   = evaluated.config.warnings;
        # Failed assertions are the ones whose `.assertion = false`. The
        # NixOS module system aggregates these and refuses to build if
        # any are non-empty (real HM does the same).
        failedAssertions = lib.filter (a: !a.assertion) evaluated.config.assertions;
      }
      else {
        success = false;
        # No message — see comment above on Nix limitation.
      };

  # ── NixOS-shaped option-set stub ────────────────────────────────────────
  # Mirrors the slice of NixOS options our `nixosModules.*` write into.
  # Same minimalism as the HM stub: structural-only; we are not validating
  # that activation snippets parse, that systemd units are well-formed,
  # etc. We only assert that evaluation succeeds/fails at the right times
  # and that the rendered values are what we expect.
  #
  # Currently covers what `nixosModules.ssh-authorized` writes
  # (users.users.<u>.openssh.authorizedKeys.keys + warnings + assertions).
  # Extend as new NixOS modules land.
  stubNixosModule = { lib, ... }: {
    options = {
      users = {
        users = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options = {
              openssh = {
                authorizedKeys = {
                  keys = lib.mkOption {
                    type    = lib.types.listOf lib.types.str;
                    default = [ ];
                  };
                };
              };
            };
          });
          default = { };
        };
      };
      warnings = lib.mkOption {
        type    = lib.types.listOf lib.types.str;
        default = [ ];
      };
      assertions = lib.mkOption {
        type    = lib.types.listOf (lib.types.submodule {
          options = {
            assertion = lib.mkOption { type = lib.types.bool; };
            message   = lib.mkOption { type = lib.types.str;  };
          };
        });
        default = [ ];
      };
    };
  };

  # ── NixOS-module eval helper ────────────────────────────────────────────
  # Same shape as `evalModule` (return `{ success; config; warnings; ... }`
  # records, propagate eval throws as `success = false`), but uses the
  # NixOS-shaped stub instead of HM-shaped. Use this from tests for
  # `nixosModules.*` modules.
  evalNixosModule = { module, config ? { }, extraArgs ? { } }:
    let
      evaluated = lib.evalModules {
        modules = [
          stubNixosModule
          module
          { inherit config; }
          { _module.args = { inherit pkgs; } // extraArgs; }
        ];
      };

      # Force the testable surface deeply enough that lazy throws
      # (e.g. revoked-in-trust) fire during eval rather than later.
      forced = builtins.deepSeq {
        inherit (evaluated.config) users warnings assertions;
      } evaluated;

      result = builtins.tryEval forced;
    in
      if result.success
      then {
        success    = true;
        config     = evaluated.config;
        assertions = evaluated.config.assertions;
        warnings   = evaluated.config.warnings;
        failedAssertions = lib.filter (a: !a.assertion) evaluated.config.assertions;
      }
      else {
        success = false;
      };

  # ── Test result aggregator ──────────────────────────────────────────────
  # Each test is `{ name; assertion = bool; }`. This collapses a list of
  # them into a `{ total; passed; failedTests = [ "[suite] testname" ] }`
  # record that the top-level default.nix aggregates across suites.
  runTests = name: tests:
    let
      results = map (t: t // { passed = t.assertion; }) tests;
      failed  = lib.filter (t: !t.passed) results;
    in {
      inherit name;
      total       = lib.length tests;
      passed      = lib.length tests - lib.length failed;
      failedTests = map (t: "[${name}] ${t.name}") failed;
    };

in {
  inherit evalModule evalNixosModule runTests;
}
