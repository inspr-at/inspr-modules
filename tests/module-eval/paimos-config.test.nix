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
  ];

in
  runTests "paimos-config" tests
