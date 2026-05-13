# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/agent-secrets.test.nix
#
# Module-eval tests for `inspr.secrets.agents`. Verifies:
#   - disabled module produces no surface (no activation script, no asserts)
#   - REQUIRED options stay required (encryptedRoot has no default — INSPR-67)
#   - undefined-hostname throws at eval time (audit fix C8 / INSPR-65 lineage)
#   - hostname can be supplied via either path (extraSpecialArgs OR option)
#   - decryptedDir default derives from home.homeDirectory
#   - identityFiles default tries ed25519 BEFORE rsa (INSPR-58)
#   - deprecated identityFile still works + emits warning (deprecation policy)
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  agentSecrets = ../../modules/home-manager/agent-secrets.nix;

  # Empty fixture — `shared/` exists but contains no .age files. Lets the
  # module evaluate cleanly (ageFilesIn returns []) without us shipping
  # bogus encrypted material in the test corpus.
  emptyRoot = ./fixtures/empty-secrets;

  # Convenience: build a "minimum-viable enabled config" we can then
  # mutate per-test. Uses a function-builder pattern (not `baseConfig //
  # { ... }`) because Nix's `//` does a SHALLOW merge — combining two
  # attrsets each containing `inspr.secrets.agents.X = ...` would only
  # keep the second's `agents` sub-attr, silently dropping the rest.
  # (Real bug caught while writing INSPR-72 — would have been an
  #  invisible test-author footgun.)
  mkConfig = extras: {
    inspr.secrets.agents = {
      enable        = true;
      encryptedRoot = emptyRoot;
      hostname      = "test-host";
    } // extras;
  };

  baseEnabled = mkConfig { };

  tests = [
    # ── Disabled-module shape ────────────────────────────────────────────
    {
      name = "disabled module evaluates cleanly with no assertions, no activation";
      assertion =
        let r = evalModule { module = agentSecrets; config = { }; };
        in r.success
           && r.failedAssertions == [ ]
           && (r.config.home.activation or { }) == { };
    }

    # ── Required-option discipline ───────────────────────────────────────
    # `encryptedRoot` has NO default (INSPR-67 / fd001ce). Enabling the
    # module without setting it must fail eval — silent zero-discovery
    # would mask consumer misconfiguration as "this host has no secrets."
    {
      name = "enabled without encryptedRoot fails eval";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = {
            inspr.secrets.agents.enable   = true;
            inspr.secrets.agents.hostname = "test-host";
            # NOT setting encryptedRoot
          };
        };
        in !r.success;
    }

    # ── Hostname undefined → eval-time throw (audit fix C8) ──────────────
    # Without a hostname (neither extraSpecialArgs nor cfg.hostname), the
    # module MUST throw at eval. The original bug was a silent literal
    # "$(hostname -s)" — looked like an interpolation but never evaluated,
    # producing zero host-specific secret discovery on every host.
    {
      name = "enabled without hostname (neither path) fails eval";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = {
            inspr.secrets.agents.enable        = true;
            inspr.secrets.agents.encryptedRoot = emptyRoot;
            # NOT setting hostname; not passing via extraArgs either
          };
        };
        in !r.success;
    }

    # ── Hostname supplied via the option → works ─────────────────────────
    {
      name = "enabled with hostname-via-option evaluates";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = baseEnabled;
        };
        in r.success && r.failedAssertions == [ ];
    }

    # ── Hostname supplied via extraSpecialArgs → works ───────────────────
    # This is the typical mkDarwinHome / nixos-rebuild path: hostname is
    # injected via `extraSpecialArgs = { inherit hostname; }`. The harness
    # routes `extraArgs.hostname` into `_module.args.hostname` for the
    # module's `{ hostname ? null }:` parameter to pick up.
    {
      name = "enabled with hostname-via-extraSpecialArgs evaluates";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          extraArgs.hostname = "test-host";
          config = {
            inspr.secrets.agents.enable        = true;
            inspr.secrets.agents.encryptedRoot = emptyRoot;
            # hostname comes from extraArgs
          };
        };
        in r.success;
    }

    # ── decryptedDir default derives from home.homeDirectory ─────────────
    # Default is `${homeDirectory}/.inspr/secrets/agents` (INSPR-164
    # canonical path doctrine, 2026-05-13). The stub sets homeDirectory =
    # "/home/test-user", so we expect that prefix.
    {
      name = "decryptedDir default derives from home.homeDirectory (canonical inspr path)";
      assertion =
        let r = evalModule { module = agentSecrets; config = { }; };
        in r.success
           && r.config.inspr.secrets.agents.decryptedDir
              == "/home/test-user/.inspr/secrets/agents";
    }

    # ── identityFiles default ordering (INSPR-58) ────────────────────────
    # ed25519 BEFORE rsa — fresh setups generate ed25519 by default; the
    # old rsa-only default broke decryption on every fresh M-series machine.
    {
      name = "identityFiles default tries ed25519 before rsa";
      assertion =
        let
          r = evalModule { module = agentSecrets; config = { }; };
          ids = r.config.inspr.secrets.agents.identityFiles;
        in r.success
           && lib.length ids >= 2
           && (lib.elemAt ids 0) == "$HOME/.ssh/id_ed25519"
           && (lib.elemAt ids 1) == "$HOME/.ssh/id_rsa";
    }

    # ── Deprecated identityFile (singular) still honored + warns ─────────
    # Per the deprecation policy (README "Versioning + deprecation policy"):
    # the old option keeps working through one MINOR cycle, with an
    # eval-time warning. Removed in v0.2.0.
    {
      name = "deprecated identityFile (singular) emits a warning when set";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = mkConfig { identityFile = "$HOME/.ssh/id_legacy"; };
        };
        in r.success
           && lib.length r.warnings >= 1
           && lib.any (w: lib.hasInfix "DEPRECATED" w) r.warnings;
    }
    {
      name = "no warning emitted when only identityFiles (plural) is used";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = baseEnabled;
        };
        in r.success && r.warnings == [ ];
    }
  ];

in
  runTests "agent-secrets" tests
