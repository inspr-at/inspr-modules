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
#   - discovery renders shared + host fixtures into decrypt loop + expected
#     set; host wins shared/host name collisions (INSPR-266)
#   - requireFiles passes on present names, fails eval on missing ones
#   - filename outside the allowed alphabet fails eval (INSPR-263)
#   - retired-dir residue warning renders; retiredDirs = [] silences (INSPR-262)
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  agentSecrets = ../../modules/home-manager/agent-secrets.nix;

  # Empty fixture — `shared/` exists (kept tracked via .gitkeep so it
  # survives into the flake source closure) but contains no .age files:
  # ageFilesIn returns [] via the dir-exists-but-empty branch.
  emptyRoot = ./fixtures/empty-secrets;

  # Populated fixture (INSPR-266) — dummy .age files whose NAMES are the
  # test payload; discovery only ever readDir-s, nothing is decrypted at
  # eval. Includes a shared/host name collision (COLLIDE.age in both).
  secretsRoot = ./fixtures/with-secrets;

  # Fixture with a filename outside the allowed alphabet — used to prove
  # the INSPR-263 eval-time name validation actually throws.
  badNamesRoot = ./fixtures/bad-names;

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

    # ── Discovery + requireFiles against real fixtures (INSPR-266) ───────
    {
      name = "discovery renders shared + host secrets into decrypt loop and expected set";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = mkConfig { encryptedRoot = secretsRoot; };
        };
        script = r.config.home.activation.materializeAgentSecrets.data;
        in r.success
           && lib.hasInfix "decrypting SHARED_ONLY" script
           && lib.hasInfix "decrypting HOST_ONLY" script
           && lib.hasInfix "SHARED_ONLY.env" script
           && lib.hasInfix "HOST_ONLY.env" script;
    }
    {
      name = "host secret overwrites shared on name collision (shared decrypts first, host last)";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = mkConfig { encryptedRoot = secretsRoot; };
        };
        script = r.config.home.activation.materializeAgentSecrets.data;
        # Path interpolation copies each fixture dir to the store on its
        # own, so sources render as .../<hash>-shared/COLLIDE.age and
        # .../<hash>-test-host/COLLIDE.age (no "host/" segment survives).
        sharedIdx = lib.strings.stringLength (lib.head (lib.splitString "-shared/COLLIDE.age" script));
        hostIdx = lib.strings.stringLength (lib.head (lib.splitString "-test-host/COLLIDE.age" script));
        in r.success
           && lib.hasInfix "-shared/COLLIDE.age" script
           && lib.hasInfix "-test-host/COLLIDE.age" script
           # allSecrets = shared ++ host, so the host decrypt runs later
           # and wins the write to the same COLLIDE.env target.
           && sharedIdx < hostIdx;
    }
    {
      name = "requireFiles naming a present secret passes eval";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = mkConfig {
            encryptedRoot = secretsRoot;
            requireFiles = [ "SHARED_ONLY" "HOST_ONLY" ];
          };
        };
        in r.success && r.failedAssertions == [ ];
    }
    {
      name = "requireFiles naming a missing secret fails eval (untracked-file guard)";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = mkConfig {
            encryptedRoot = secretsRoot;
            requireFiles = [ "NOT_THERE" ];
          };
        };
        in !r.success;
    }
    {
      name = "secret filename outside the allowed alphabet fails eval (INSPR-263 validation)";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = mkConfig { encryptedRoot = badNamesRoot; };
        };
        in !r.success;
    }
    {
      name = "empty fixture renders no decrypt lines but still a full lifecycle script";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = baseEnabled;
        };
        script = r.config.home.activation.materializeAgentSecrets.data;
        in r.success
           && !(lib.hasInfix "decrypting" script)
           && lib.hasInfix "Cleanup orphans" script;
    }

    # ── Retired-dir residue check (INSPR-262) ────────────────────────────
    {
      name = "activation renders the retired-dir residue warning for the legacy default";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = baseEnabled;
        };
        script = r.config.home.activation.materializeAgentSecrets.data;
        in r.success
           && lib.hasInfix "retired secrets dir" script
           && lib.hasInfix "/Secrets/age/decrypted/agents" script
           # warn-only contract: the residue block must not delete anything
           && !(lib.hasInfix "rm -rf \"$RETIRED\"" script);
    }
    {
      name = "retiredDirs = [ ] silences the residue check";
      assertion =
        let r = evalModule {
          module = agentSecrets;
          config = mkConfig { retiredDirs = [ ]; };
        };
        in r.success
           && !(lib.hasInfix "retired secrets dir"
                  r.config.home.activation.materializeAgentSecrets.data);
    }
  ];

in
  runTests "agent-secrets" tests
