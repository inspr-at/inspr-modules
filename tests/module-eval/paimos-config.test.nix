# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/paimos-config.test.nix
#
# Module-eval tests for `inspr.paimos-cli`. Verifies the two assertions
# added in the audit pass (INSPR-54 + INSPR-69):
#   - instances ≠ {}                                  (H3 / O6)
#   - defaultInstance ∈ instances                     (H3)
#
# Plus baseline option-shape tests (disabled produces no surface, well-
# formed config eval succeeds, instance schema is enforced).
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  paimosConfig = ../../modules/home-manager/paimos-config.nix;

  # A well-formed instance shape — used as the building block for the
  # "happy path" tests so we're not repeating the schema everywhere.
  validInstance = {
    url           = "https://paimos.example.com";
    apiKeyEnvFile = "/run/agenix/paimos-key";
    apiKeyVar     = "PAIMOS_API_KEY";
  };

  tests = [
    # ── Disabled-module shape ────────────────────────────────────────────
    {
      name = "disabled module evaluates cleanly with no assertions, no activation";
      assertion =
        let r = evalModule { module = paimosConfig; config = { }; };
        in r.success
           && r.failedAssertions == [ ]
           && (r.config.home.activation or { }) == { };
    }

    # ── Assertion: instances ≠ {} (INSPR-54 / audit O6) ──────────────────
    # Enabling without declaring any instance is a misconfiguration —
    # the resulting config.yaml would have an empty `instances:` block
    # and `paimos` would fail at runtime with cryptic "instance not
    # configured" errors. Catch it at switch time.
    {
      name = "enabled with empty instances triggers assertion failure";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable          = true;
            inspr.paimos-cli.defaultInstance = "anything";
            # instances defaults to {}
          };
        };
        in r.success
           && lib.length r.failedAssertions >= 1
           && lib.any (a: lib.hasInfix "at least one entry" a.message)
                      r.failedAssertions;
    }

    # ── Assertion: defaultInstance ∈ instances (INSPR-69 / audit H3) ─────
    # Typo or stale rename in defaultInstance is the most common
    # consumer-side misconfig. Without this assertion, the materialized
    # config.yaml would name a non-existent default and fail at the
    # paimos CLI's first invocation. Loud > silent.
    {
      name = "enabled with defaultInstance not in instances triggers assertion failure";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable          = true;
            inspr.paimos-cli.defaultInstance = "missing";
            inspr.paimos-cli.instances.real  = validInstance;
          };
        };
        in r.success
           && lib.length r.failedAssertions >= 1
           && lib.any (a: lib.hasInfix "must be a key" a.message)
                      r.failedAssertions;
    }

    # ── Happy path: well-formed config evaluates with no failed assertions
    {
      name = "well-formed enabled config has no failed assertions";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable          = true;
            inspr.paimos-cli.defaultInstance = "real";
            inspr.paimos-cli.instances.real  = validInstance;
          };
        };
        in r.success && r.failedAssertions == [ ];
    }

    # ── Multi-instance config evaluates ──────────────────────────────────
    # Confirms the option type accepts attrsOf and the assertion logic
    # (`lib.elem defaultInstance (attrNames instances)`) handles >1 entry.
    {
      name = "multi-instance config with valid default evaluates cleanly";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable          = true;
            inspr.paimos-cli.defaultInstance = "prod";
            inspr.paimos-cli.instances = {
              prod    = validInstance;
              staging = validInstance // { url = "https://staging.example.com"; };
              local   = validInstance // { url = "http://localhost:8000";       };
            };
          };
        };
        in r.success && r.failedAssertions == [ ];
    }

    # ── Schema enforcement: instance with missing required field fails ───
    # `apiKeyVar` is required (no default). Submitting an instance
    # without it must fail eval — proves the submodule type check is
    # actually wired up, not just decorative.
    {
      name = "instance missing required apiKeyVar fails eval";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable          = true;
            inspr.paimos-cli.defaultInstance = "broken";
            inspr.paimos-cli.instances.broken = {
              url           = "https://x.example.com";
              apiKeyEnvFile = "/some/path";
              # apiKeyVar omitted
            };
          };
        };
        in !r.success;
    }

    # ── INSPR-174: urlEnvFile + urlVar instance evaluates cleanly ────────
    # Happy path for the new URL-from-env-file option. PMO-shaped instance
    # where URL comes from agenix-encrypted env file rather than Nix literal.
    {
      name = "INSPR-174: instance with urlEnvFile + urlVar evaluates cleanly";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable          = true;
            inspr.paimos-cli.defaultInstance = "work";
            inspr.paimos-cli.instances.work = {
              urlEnvFile    = "/run/agenix/work-url";
              urlVar        = "WORKURL";
              apiKeyEnvFile = "/run/agenix/work-api-key";
              apiKeyVar     = "WORKAPIKEY";
            };
          };
        };
        in r.success && r.failedAssertions == [ ];
    }

    # ── INSPR-174: both url AND urlEnvFile set → assertion fires ─────────
    # Mutual exclusion: declaring both is ambiguous. Catch at eval time.
    {
      name = "INSPR-174: instance with both url and urlEnvFile triggers assertion";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable          = true;
            inspr.paimos-cli.defaultInstance = "conflict";
            inspr.paimos-cli.instances.conflict = {
              url           = "https://x.example.com";
              urlEnvFile    = "/run/agenix/x-url";
              urlVar        = "XURL";
              apiKeyEnvFile = "/run/agenix/x-key";
              apiKeyVar     = "XAPIKEY";
            };
          };
        };
        in r.success
           && lib.any (a: lib.hasInfix "exactly ONE of" a.message)
                      r.failedAssertions;
    }

    # ── INSPR-174: neither url nor urlEnvFile set → assertion fires ──────
    # Same invariant from the other side: forgetting both is invalid.
    {
      name = "INSPR-174: instance with neither url nor urlEnvFile triggers assertion";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable          = true;
            inspr.paimos-cli.defaultInstance = "noUrl";
            inspr.paimos-cli.instances.noUrl = {
              # both url and urlEnvFile omitted (default null)
              apiKeyEnvFile = "/run/agenix/k";
              apiKeyVar     = "KEY";
            };
          };
        };
        in r.success
           && lib.any (a: lib.hasInfix "exactly ONE of" a.message)
                      r.failedAssertions;
    }

    # ── INSPR-174: urlEnvFile set but urlVar null → assertion fires ──────
    # urlEnvFile alone is useless — we need urlVar to know what to extract.
    {
      name = "INSPR-174: urlEnvFile without urlVar triggers assertion";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable          = true;
            inspr.paimos-cli.defaultInstance = "incomplete";
            inspr.paimos-cli.instances.incomplete = {
              urlEnvFile    = "/run/agenix/x";
              # urlVar omitted
              apiKeyEnvFile = "/run/agenix/k";
              apiKeyVar     = "KEY";
            };
          };
        };
        in r.success
           && lib.any (a: lib.hasInfix "urlVar is null" a.message)
                      r.failedAssertions;
    }
  ];

in
  runTests "paimos-config" tests
