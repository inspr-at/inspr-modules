# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/devenv-direnv-fix.test.nix
#
# Module-eval tests for `inspr.devenv.direnv-fix` (INSPR-175).
#
# Scope: disabled-state shape only.
#
# The interesting work happens inside the `patchedDirenvrc` build-time
# derivation (`devenv direnvrc | sed`), which the module-eval harness can't
# safely exercise: the harness `deepSeq`s through `home.file.*.source`,
# which (when enabled) is a runCommand derivation pulling in stdenv —
# stdenv eval recurses past Nix's call-depth limit on Darwin (sandbox-
# profile attribute eval). Stub devenv packages still trigger the same
# recursion path through `pkgs.runCommand`.
#
# Build-time correctness is instead verified two ways:
#   1. The module's own `patchedDirenvrc` derivation has built-in sanity
#      asserts that FAIL the build (with a clear INSPR-175 message) if
#      the `sed` rename produced no `_devenv_preflight` markers OR left
#      any `_nix_direnv_preflight` markers behind.
#   2. Real HM activation on workstation — rebuild succeeding + the file
#      appearing at `~/.config/direnv/lib/z-devenv.sh` proves the
#      derivation built successfully. The end-to-end test (both
#      `use nix` and `use devenv` work) is the actual acceptance check.
#
# So: this file is an option-shape sanity belt only. The rest is
# upstream of the harness.
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  module = ../../modules/home-manager/devenv-direnv-fix.nix;

  tests = [
    {
      name = "disabled module produces no home.file entry";
      assertion =
        let r = evalModule { module = module; config = { }; };
        in r.success
           && (r.config.home.file or { }) == { };
    }

    {
      name = "module imports cleanly + option submodule type accepts custom targetPath in disabled state";
      assertion =
        let r = evalModule {
          module = module;
          # enable left false; just verify the option type accepts the field
          config = {
            inspr.devenv.direnv-fix.targetPath = ".local/share/direnv/lib/z-devenv.sh";
          };
        };
        in r.success
           && (r.config.home.file or { }) == { };
    }
  ];

in
  runTests "devenv-direnv-fix" tests
