# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/git-identity.test.nix
#
# Module-eval tests for `inspr.git-identity`. Verifies:
#   - disabled module produces no programs.git config
#   - enabled module sets programs.git.settings.user from the default identity
#   - referencing an undeclared identity (in `default` or in a context)
#     throws at eval time — silent fall-back to wrong identity would be a
#     real-world footgun (commits with the wrong author email).
#   - context includes are emitted (one per gitdir + one per remoteUrlPattern)
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  gitIdentity = ../../modules/home-manager/git-identity.nix;

  # Two-identity baseline used by most tests.
  baseIdentities = {
    personal = { name = "Test User"; email = "test@example.com";   };
    work     = { name = "Test User"; email = "test@employer.com";  };
  };

  tests = [
    # ── Disabled-module shape ────────────────────────────────────────────
    {
      name = "disabled module evaluates cleanly with no programs.git config";
      assertion =
        let r = evalModule { module = gitIdentity; config = { }; };
        in r.success
           && (r.config.programs.git or { }) == { };
    }

    # ── Enabled with valid default identity ──────────────────────────────
    {
      name = "enabled with valid default sets programs.git.settings.user";
      assertion =
        let r = evalModule {
          module = gitIdentity;
          config = {
            inspr.git-identity.enable     = true;
            inspr.git-identity.default    = "personal";
            inspr.git-identity.identities = baseIdentities;
          };
        };
        in r.success
           && r.config.programs.git.settings.user.name  == "Test User"
           && r.config.programs.git.settings.user.email == "test@example.com";
    }

    # ── default = undeclared-identity → throws ───────────────────────────
    # The module's `identityByName` helper throws with a clear error
    # listing the declared identities. This is the eval-time equivalent
    # of "you renamed an identity but forgot to update `default`."
    {
      name = "default referencing undeclared identity fails eval";
      assertion =
        let r = evalModule {
          module = gitIdentity;
          config = {
            inspr.git-identity.enable     = true;
            inspr.git-identity.default    = "nonexistent";
            inspr.git-identity.identities = baseIdentities;
          };
        };
        in !r.success;
    }

    # ── context.identity = undeclared → throws ───────────────────────────
    # Same throw, but triggered via a context's `identity =` field. This
    # is the "renamed identity but forgot to update one of the contexts"
    # variant — tested separately because contexts evaluate lazily and
    # could in principle skip the check if no includes were rendered.
    {
      name = "context referencing undeclared identity fails eval";
      assertion =
        let r = evalModule {
          module = gitIdentity;
          config = {
            inspr.git-identity.enable     = true;
            inspr.git-identity.default    = "personal";
            inspr.git-identity.identities = baseIdentities;
            inspr.git-identity.contexts.broken = {
              identity  = "ghost";
              gitdirs   = [ "~/Code/Broken/" ];
            };
          };
        };
        in !r.success;
    }

    # ── Context includes get emitted (count check) ───────────────────────
    # One include per gitdir + one per remoteUrlPattern. With 1 gitdir +
    # 2 remote patterns we expect 3 include entries total.
    {
      name = "context with 1 gitdir + 2 remoteUrlPatterns emits 3 includes";
      assertion =
        let r = evalModule {
          module = gitIdentity;
          config = {
            inspr.git-identity.enable     = true;
            inspr.git-identity.default    = "personal";
            inspr.git-identity.identities = baseIdentities;
            inspr.git-identity.contexts.work = {
              identity = "work";
              gitdirs  = [ "~/Code/Work/" ];
              remoteUrlPatterns = [
                "https://github.com/employer/**"
                "**:employer/**"
              ];
            };
          };
        };
        in r.success
           && lib.length r.config.programs.git.includes == 3;
    }

    # ── Context with no patterns → no includes (empty contexts are no-op)
    # Lets consumers declare a context skeleton without committing to its
    # match conditions yet (e.g., during a migration). Should not error.
    {
      name = "context with no gitdirs and no remoteUrlPatterns emits 0 includes";
      assertion =
        let r = evalModule {
          module = gitIdentity;
          config = {
            inspr.git-identity.enable     = true;
            inspr.git-identity.default    = "personal";
            inspr.git-identity.identities = baseIdentities;
            inspr.git-identity.contexts.placeholder = {
              identity = "work";
              # gitdirs + remoteUrlPatterns default to []
            };
          };
        };
        in r.success
           && r.config.programs.git.includes == [ ];
    }
  ];

in
  runTests "git-identity" tests
