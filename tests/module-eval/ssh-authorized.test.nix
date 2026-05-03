# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/ssh-authorized.test.nix
#
# Module-eval tests for `inspr.ssh.authorized`. Verifies:
#   - disabled module produces no activation script
#   - enabled with empty trust emits a warning (not an error)
#   - enabled with valid trust admits exactly the named keys
#   - trust referencing an undeclared alias throws at eval time
#     (silent-skip would be a real footgun — sshd ignores empty-body
#      lines, so the host would just stop trusting that alias)
#   - sortedTrust ordering: `trust = [ "b" "a" ]` and `trust = [ "a" "b" ]`
#     produce the same managed block (determinism / git-noise reduction)
#   - custom markers are honored end-to-end (override path)
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  sshAuthorized = ../../modules/home-manager/ssh-authorized.nix;

  # Two-key baseline used by most tests.
  baseKeys = {
    "alice@m1" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA0000000000000000000000000000000000000000000 alice@m1";
    "bob@m2"   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA1111111111111111111111111111111111111111111 bob@m2";
  };

  # Helper: extract the activation script string for the ssh-authorized
  # entry. Returns "" if the module didn't emit one (disabled case).
  activationFor = r:
    let entry = r.config.home.activation.insprSshAuthorized or null;
    in if entry == null then ""
       else if builtins.isAttrs entry && entry ? data then entry.data
       else if builtins.isString entry then entry
       else "";

  tests = [
    # ── Disabled-module shape ────────────────────────────────────────────
    {
      name = "disabled module evaluates cleanly with no activation script";
      assertion =
        let r = evalModule { module = sshAuthorized; config = { }; };
        in r.success
           && (r.config.home.activation.insprSshAuthorized or null) == null;
    }

    # ── Enabled with empty trust → warning, no error ─────────────────────
    {
      name = "enabled with empty trust evaluates cleanly with a warning";
      assertion =
        let r = evalModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            # trust deliberately omitted (defaults to [ ])
          };
        };
        in r.success
           && lib.length r.config.warnings == 1
           && lib.hasInfix "trust` is empty" (lib.elemAt r.config.warnings 0);
    }

    # ── Enabled with valid trust → activation script references each key
    # The script bakes the managed block into a /nix/store file and
    # references it by store path. We can't directly inspect the block
    # contents from here without IFD, but we can assert the activation
    # script was emitted (i.e. `lib.mkIf cfg.enable` fired) and that no
    # warning leaked through.
    {
      name = "enabled with valid trust emits activation entry, no warnings";
      assertion =
        let r = evalModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            inspr.ssh.authorized.trust  = [ "alice@m1" "bob@m2" ];
          };
        };
        in r.success
           && (r.config.home.activation.insprSshAuthorized or null) != null
           && r.config.warnings == [ ]
           && lib.hasInfix "2 keys admitted" (activationFor r);
    }

    # ── trust = [ undeclared-alias ] → throws ────────────────────────────
    # The module's `keyByAlias` helper throws with a clear error listing
    # the declared aliases. This is the eval-time equivalent of "you
    # renamed a key but forgot to update `trust`."
    {
      name = "trust referencing undeclared alias fails eval";
      assertion =
        let r = evalModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            inspr.ssh.authorized.trust  = [ "ghost" ];
          };
        };
        in !r.success;
    }

    # ── trust referencing one valid + one invalid → still throws ─────────
    # Confirms the throw fires even if some aliases resolve. (Lazy-eval
    # could in principle short-circuit if we stopped at the first valid
    # entry — this test catches a regression in that direction.)
    {
      name = "trust with one valid + one invalid alias fails eval";
      assertion =
        let r = evalModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = baseKeys;
            inspr.ssh.authorized.trust  = [ "alice@m1" "ghost" ];
          };
        };
        in !r.success;
    }

    # ── Determinism: input order doesn't affect output ───────────────────
    # Two evaluations with the same trust set in different orders should
    # produce byte-identical activation scripts. We compare the activation
    # script strings directly.
    {
      name = "trust = [b a] and trust = [a b] produce identical activation scripts";
      assertion =
        let
          mkR = trust: evalModule {
            module = sshAuthorized;
            config = {
              inspr.ssh.authorized.enable = true;
              inspr.ssh.authorized.keys   = baseKeys;
              inspr.ssh.authorized.trust  = trust;
            };
          };
          rAB = mkR [ "alice@m1" "bob@m2" ];
          rBA = mkR [ "bob@m2"   "alice@m1" ];
        in
          rAB.success && rBA.success
          && activationFor rAB == activationFor rBA;
    }

    # ── Custom markers honored ───────────────────────────────────────────
    # If a consumer overrides markerBegin/markerEnd, the activation script
    # must reference the new markers (not the defaults). We verify the
    # custom string appears in the rendered activation.
    {
      name = "custom marker strings appear in activation script";
      assertion =
        let r = evalModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable      = true;
            inspr.ssh.authorized.keys        = baseKeys;
            inspr.ssh.authorized.trust       = [ "alice@m1" ];
            inspr.ssh.authorized.markerBegin = "# CUSTOM_BEGIN_MARKER";
            inspr.ssh.authorized.markerEnd   = "# CUSTOM_END_MARKER";
          };
        };
        in r.success
           && lib.hasInfix "CUSTOM_BEGIN_MARKER" (activationFor r)
           && lib.hasInfix "CUSTOM_END_MARKER"   (activationFor r);
    }

    # ── trust with no keys at all (empty `keys`) but non-empty `trust` ──
    # Edge case: `keys = { }` and `trust = [ "anything" ]` should throw,
    # because every alias in trust is undeclared. Confirms the throw
    # fires from the empty-attrs path too.
    {
      name = "non-empty trust against empty keys fails eval";
      assertion =
        let r = evalModule {
          module = sshAuthorized;
          config = {
            inspr.ssh.authorized.enable = true;
            inspr.ssh.authorized.keys   = { };
            inspr.ssh.authorized.trust  = [ "anything" ];
          };
        };
        in !r.success;
    }
  ];

in
  runTests "ssh-authorized" tests
