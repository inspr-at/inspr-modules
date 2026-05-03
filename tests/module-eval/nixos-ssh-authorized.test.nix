# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/nixos-ssh-authorized.test.nix
#
# Module-eval tests for `nixosModules.ssh-authorized` (INSPR-73 — system-side
# counterpart to the HM module). Verifies:
#   - disabled module produces no users.users.* entries
#   - enabled with empty `users` emits a warning (not an error)
#   - enabled with valid trust renders the right keys (in sorted order)
#   - trust referencing an undeclared alias throws at eval time
#   - revoked alias in trust throws at eval time (the "I forgot to remove
#     from trust" footgun guard)
#   - revoked alias NOT in trust evaluates cleanly (declaration preserved)
#   - extraKeys are appended after the trust-resolved keys (raw, no
#     status machinery)
#   - sortedTrust ordering: input order does not affect output (determinism)
#   - mixed string + rich keys in same keyring map both work
#   - multi-user: two users get independent rendering
#   - force = true wraps the rendered list in lib.mkForce (test by
#     observing it overrides a competing declaration)
#   - force = false (default) merges with competing declarations
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalNixosModule runTests;

  sshAuthorized = ../../modules/nixos/ssh-authorized.nix;

  # Two-key baseline keyring used by most tests.
  baseKeys = {
    "alice@m1" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA0000000000000000000000000000000000000000000 alice@m1";
    "bob@m2"   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA1111111111111111111111111111111111111111111 bob@m2";
  };

  # Helper: extract the rendered key list for a given user.
  keysFor = r: uname:
    r.config.users.users.${uname}.openssh.authorizedKeys.keys or [ ];

  tests = [
    # ── Disabled-module shape ────────────────────────────────────────────
    {
      name = "disabled module evaluates cleanly with no users.users entries";
      assertion =
        let r = evalNixosModule { module = sshAuthorized; config = { }; };
        in r.success
           && r.config.users.users == { };
    }

    # ── Enabled with empty users → warning, no error ─────────────────────
    {
      name = "enabled with empty users evaluates cleanly with a warning";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            # users deliberately omitted (defaults to {})
          };
        };
        in r.success
           && lib.length r.config.warnings == 1
           && lib.hasInfix "users` is empty" (lib.elemAt r.config.warnings 0);
    }

    # ── Enabled with valid trust → keys rendered in sorted order ─────────
    {
      name = "enabled with valid trust renders both keys in sorted order";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            inspr.ssh.authorized.users.mba.trust = [ "bob@m2" "alice@m1" ];
          };
        };
        in r.success
           && r.config.warnings == [ ]
           && keysFor r "mba" == [ baseKeys."alice@m1" baseKeys."bob@m2" ];
    }

    # ── trust = [ undeclared-alias ] → throws ────────────────────────────
    {
      name = "trust referencing undeclared alias fails eval";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            inspr.ssh.authorized.users.mba.trust = [ "ghost" ];
          };
        };
        in !r.success;
    }

    # ── trust referencing one valid + one invalid → still throws ─────────
    {
      name = "trust with one valid + one invalid alias fails eval";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            inspr.ssh.authorized.users.mba.trust = [ "alice@m1" "ghost" ];
          };
        };
        in !r.success;
    }

    # ── Determinism: input order does not affect output ──────────────────
    {
      name = "trust = [b a] and trust = [a b] produce identical rendered key lists";
      assertion =
        let
          mkR = trust: evalNixosModule {
            module = sshAuthorized;
            config = {
              inspr.ssh.authorized.enable = true;
              inspr.ssh.authorized.keys   = baseKeys;
              inspr.ssh.authorized.users.mba.trust = trust;
            };
          };
          rAB = mkR [ "alice@m1" "bob@m2" ];
          rBA = mkR [ "bob@m2"   "alice@m1" ];
        in
          rAB.success && rBA.success
          && keysFor rAB "mba" == keysFor rBA "mba";
    }

    # ── Mixed string + rich keys in same keyring ─────────────────────────
    {
      name = "mixed string + rich keys in same keyring both work";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys = {
              "alice@simple" = baseKeys."alice@m1";  # bare string
              "bob-rich" = {                          # rich form
                key    = baseKeys."bob@m2";
                status = "active";
              };
            };
            inspr.ssh.authorized.users.mba.trust = [ "alice@simple" "bob-rich" ];
          };
        };
        in r.success
           && r.config.warnings == [ ]
           && lib.length (keysFor r "mba") == 2;
    }

    # ── status=legacy is admitted (no decoration in NixOS render) ────────
    {
      name = "rich form status=legacy is admitted (no decoration in NixOS render)";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys = {
              "shared-rsa-pre-2026" = {
                key    = "ssh-rsa AAAAB3NzaC1yc2EAAAA0000 markus";
                status = "legacy";
                note   = "shared pre-2026 RSA";
              };
            };
            inspr.ssh.authorized.users.mba.trust = [ "shared-rsa-pre-2026" ];
          };
        };
        in r.success
           && r.config.warnings == [ ]
           && keysFor r "mba" == [ "ssh-rsa AAAAB3NzaC1yc2EAAAA0000 markus" ];
    }

    # ── status=revoked + alias IN trust → throws ─────────────────────────
    # The "did you forget to remove from trust" footgun guard.
    {
      name = "revoked alias in trust fails eval";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys = {
              "old-deploy-key" = {
                key    = "ssh-ed25519 AAAA... old-deploy";
                status = "revoked";
                note   = "compromised; retired";
              };
            };
            inspr.ssh.authorized.users.mba.trust = [ "old-deploy-key" ];
          };
        };
        in !r.success;
    }

    # ── status=revoked + alias NOT in trust → succeeds ───────────────────
    # Intended terminal state for retired keys: declaration preserved as
    # historical record, but no admittance.
    {
      name = "revoked alias absent from trust evaluates cleanly (declaration preserved)";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys = {
              "old-deploy-key" = {
                key    = "ssh-ed25519 AAAA... old-deploy";
                status = "revoked";
                note   = "compromised; retired";
              };
              "current-deploy" = baseKeys."alice@m1";
            };
            inspr.ssh.authorized.users.mba.trust = [ "current-deploy" ];
          };
        };
        in r.success
           && r.config.warnings == [ ]
           && keysFor r "mba" == [ baseKeys."alice@m1" ];
    }

    # ── extraKeys are appended after trust-resolved keys ─────────────────
    {
      name = "extraKeys are appended (raw, after trust-resolved keys)";
      assertion =
        let
          extra = "ssh-ed25519 AAAA... container-deploy";
          r = evalNixosModule {
            module = sshAuthorized;
            config = {
              inspr.ssh.authorized.enable = true;
              inspr.ssh.authorized.keys   = baseKeys;
              inspr.ssh.authorized.users.mba = {
                trust     = [ "alice@m1" ];
                extraKeys = [ extra ];
              };
            };
          };
        in r.success
           && keysFor r "mba" == [ baseKeys."alice@m1" extra ];
    }

    # ── Multi-user: two users get independent rendering ──────────────────
    {
      name = "two users with different trust lists render independently";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            inspr.ssh.authorized.users = {
              mba.trust = [ "alice@m1" "bob@m2" ];
              gb.trust  = [ "alice@m1" ];
            };
          };
        };
        in r.success
           && keysFor r "mba" == [ baseKeys."alice@m1" baseKeys."bob@m2" ]
           && keysFor r "gb"  == [ baseKeys."alice@m1" ];
    }

    # ── force = true overrides a competing declaration ───────────────────
    # Simulates the hokage server-home injection scenario: another module
    # contributes a key, and `force = true` makes ours win (replace, not
    # merge). We feed in a competing `users.users.mba.openssh.authorizedKeys.keys`
    # via the test config to mimic that injection.
    {
      name = "force = true overrides competing users.users declaration";
      assertion =
        let r = evalNixosModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            inspr.ssh.authorized.users.mba = {
              trust = [ "alice@m1" ];
              force = true;
            };
            # Competing declaration — should be displaced by mkForce.
            users.users.mba.openssh.authorizedKeys.keys = [
              "ssh-rsa AAAA... external-injection"
            ];
          };
        };
        in r.success
           && keysFor r "mba" == [ baseKeys."alice@m1" ];
    }

    # ── force = false (default) merges with competing declarations ───────
    # NixOS list options merge by concatenation. Without force, both
    # contributions appear. Order between the two contributions is
    # implementation-defined; we just check both keys are present.
    {
      name = "force = false (default) merges with competing declarations";
      assertion =
        let
          competing = "ssh-rsa AAAA... other-source";
          r = evalNixosModule {
            module = sshAuthorized;
            config = {
              inspr.ssh.authorized.enable = true;
              inspr.ssh.authorized.keys   = baseKeys;
              inspr.ssh.authorized.users.mba.trust = [ "alice@m1" ];
              # No `force` set; default false. Competing declaration:
              users.users.mba.openssh.authorizedKeys.keys = [ competing ];
            };
          };
          rendered = keysFor r "mba";
        in r.success
           && lib.length rendered == 2
           && lib.elem baseKeys."alice@m1" rendered
           && lib.elem competing rendered;
    }
  ];

in
  runTests "nixos-ssh-authorized" tests
