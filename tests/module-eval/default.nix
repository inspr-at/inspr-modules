# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/default.nix
#
# Entry point for the module-eval test suite. Imports every *.test.nix
# file in this directory and aggregates their per-suite results into a
# structured result: { ok; report; totalRun; totalPassed; failedTests; }.
#
# NO THROW on failure (INSPR-267): a throw here became a flake-EVAL error
# that broke `nix flake show` and aborted check enumeration for every
# sibling check. The pass/fail decision now lives in the
# `flake.checks.<system>.module-eval` derivation, which exits non-zero on
# `failedTests != []` — a red unit test fails as one ordinary check.
#
# Add a new suite by adding it to the `testFiles` list below.
# ─────────────────────────────────────────────────────────────────────────
{ pkgs, lib, homeManagerModules ? { }, nixosModules ? { } }:

let
  harness = import ./harness.nix { inherit lib pkgs; } // {
    # Exposed on the harness so no test signature changes; only
    # exports-importable.test.nix reads them.
    inherit homeManagerModules nixosModules;
  };

  testFiles = [
    ./agent-secrets.test.nix
    ./agent-skills.test.nix
    ./devenv-direnv-fix.test.nix
    ./git-atelier-credentials.test.nix
    ./git-identity.test.nix
    ./paimos-config.test.nix
    ./ssh-authorized.test.nix
    ./nixos-ssh-authorized.test.nix
    ./exports-importable.test.nix
  ];

  results = map (f: import f { inherit harness lib; }) testFiles;

  totalRun    = lib.foldl' (a: r: a + r.total)  0 results;
  totalPassed = lib.foldl' (a: r: a + r.passed) 0 results;
  allFailed   = lib.concatLists (map (r: r.failedTests) results);

  perSuiteSummary = lib.concatMapStringsSep "\n" (r:
    "  ${r.name}: ${toString r.passed}/${toString r.total}"
  ) results;

  report =
    if allFailed == [ ]
    then ''
      ✓ ALL ${toString totalPassed}/${toString totalRun} MODULE-EVAL TESTS PASSED

      Per-suite:
      ${perSuiteSummary}
    ''
    else ''

      ✗ MODULE-EVAL TESTS FAILED — ${toString (lib.length allFailed)}/${toString totalRun} failed:

      ${lib.concatMapStringsSep "\n" (t: "  ✗ ${t}") allFailed}

      Per-suite:
      ${perSuiteSummary}
    '';

in
{
  ok = allFailed == [ ];
  inherit report totalRun totalPassed;
  failedTests = allFailed;
}
