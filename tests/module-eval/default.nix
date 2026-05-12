# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/default.nix
#
# Entry point for the module-eval test suite. Imports every *.test.nix
# file in this directory and aggregates their per-suite results into a
# single PASS/FAIL summary. On failure, throws with a list of failed
# test names — Nix surfaces the throw as an eval error, which the
# `flake.checks.<system>.module-eval` derivation catches as build failure.
#
# Add a new suite by adding it to the `testFiles` list below.
# ─────────────────────────────────────────────────────────────────────────
{ pkgs, lib }:

let
  harness = import ./harness.nix { inherit lib pkgs; };

  testFiles = [
    ./agent-secrets.test.nix
    ./devenv-direnv-fix.test.nix
    ./git-atelier-credentials.test.nix
    ./git-identity.test.nix
    ./paimos-config.test.nix
    ./ssh-authorized.test.nix
    ./nixos-ssh-authorized.test.nix
  ];

  results = map (f: import f { inherit harness lib; }) testFiles;

  totalRun    = lib.foldl' (a: r: a + r.total)  0 results;
  totalPassed = lib.foldl' (a: r: a + r.passed) 0 results;
  allFailed   = lib.concatLists (map (r: r.failedTests) results);

  perSuiteSummary = lib.concatMapStringsSep "\n" (r:
    "  ${r.name}: ${toString r.passed}/${toString r.total}"
  ) results;

in
  if allFailed == [ ]
  then ''
    ✓ ALL ${toString totalPassed}/${toString totalRun} MODULE-EVAL TESTS PASSED

    Per-suite:
    ${perSuiteSummary}
  ''
  else throw ''

    ✗ MODULE-EVAL TESTS FAILED — ${toString (lib.length allFailed)}/${toString totalRun} failed:

    ${lib.concatMapStringsSep "\n" (t: "  ✗ ${t}") allFailed}

    Per-suite:
    ${perSuiteSummary}
  ''
