# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/paimos-config.test.nix
#
# Module-eval tests for declarative Paimos routing. Authentication is outside
# this module: workstation credentials live in the OS keyring after interactive
# login, while headless credentials are process-runtime inputs only.
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  paimosConfig = ../../modules/home-manager/paimos-config.nix;

  validInstance = {
    url = "https://paimos.example.com";
  };

  evalEnabled = instance: evalModule {
    module = paimosConfig;
    config = {
      inspr.paimos-cli.enable = true;
      inspr.paimos-cli.defaultInstance = "real";
      inspr.paimos-cli.instances.real = instance;
    };
  };

  activationData = result:
    result.config.home.activation.bootstrapPaimosConfig.data;

  beforeAtomicMove = activation:
    builtins.head (lib.splitString ''mv -f "$tmp"'' activation);

  beforeTempCreation = activation:
    builtins.head (lib.splitString "tmp=\"$(mktemp" activation);

  compatibilityInstance = validInstance // {
    apiKeyEnvFile = "/compat/secret-file-marker";
    apiKeyVar = "SECRET_VARIABLE_MARKER";
  };

  urlEnvInstance = {
    urlEnvFile = "/routing/url-file-marker";
    urlVar = "ROUTING_URL_MARKER";
    apiKeyEnvFile = "/compat/env-secret-file-marker";
    apiKeyVar = "ENV_SECRET_VARIABLE_MARKER";
  };

  tests = [
    {
      name = "disabled module evaluates cleanly with no assertions or activation";
      assertion =
        let r = evalModule { module = paimosConfig; config = { }; };
        in r.success
           && r.failedAssertions == [ ]
           && r.warnings == [ ]
           && (r.config.home.activation or { }) == { };
    }

    {
      name = "enabled with empty instances triggers assertion failure";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable = true;
            inspr.paimos-cli.defaultInstance = "anything";
          };
        };
        in r.success
           && lib.any (a: lib.hasInfix "at least one entry" a.message)
                      r.failedAssertions;
    }

    {
      name = "defaultInstance not in instances triggers assertion failure";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable = true;
            inspr.paimos-cli.defaultInstance = "missing";
            inspr.paimos-cli.instances.real = validInstance;
          };
        };
        in r.success
           && lib.any (a: lib.hasInfix "must be a key" a.message)
                      r.failedAssertions;
    }

    {
      name = "literal URL renders an exactly nested instances mapping";
      assertion =
        let
          r = evalEnabled validInstance;
          activation = activationData r;
        in r.success
           && r.failedAssertions == [ ]
           && r.warnings == [ ]
           && lib.hasInfix ''default_instance: "real"'' activation
           && lib.hasInfix "instances:" activation
           && lib.hasInfix "  \"real\":\n    url: \"https://paimos.example.com\""
                          activation;
    }

    {
      name = "multi-instance routing evaluates cleanly";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable = true;
            inspr.paimos-cli.defaultInstance = "prod";
            inspr.paimos-cli.instances = {
              prod = validInstance;
              staging.url = "https://staging.example.com";
              local.url = "http://localhost:8000";
            };
          };
        };
        in r.success
           && r.failedAssertions == [ ]
           && lib.hasInfix ''url: "https://staging.example.com"''
                          (activationData r);
    }

    {
      name = "instance with neither URL source triggers XOR assertion";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable = true;
            inspr.paimos-cli.defaultInstance = "broken";
            inspr.paimos-cli.instances.broken = { };
          };
        };
        in r.success
           && lib.any (a: lib.hasInfix "exactly ONE of" a.message)
                      r.failedAssertions;
    }

    {
      name = "URL env file renders an exactly nested runtime mapping";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable = true;
            inspr.paimos-cli.defaultInstance = "work";
            inspr.paimos-cli.instances.work = urlEnvInstance;
          };
        };
        activation = activationData r;
        in r.success
           && r.failedAssertions == [ ]
           && lib.hasInfix "/routing/url-file-marker" activation
           && lib.hasInfix "ROUTING_URL_MARKER" activation
           && lib.hasInfix "/bin/printenv -- ROUTING_URL_MARKER" activation
           && lib.hasInfix "printf '%s\\n' '  \"work\":'" activation
           && lib.hasInfix "/bin/jq -Rn --arg value \"$url_value\" '$value')" activation
           && lib.hasInfix ''printf '    url: %s\n' "$url_encoded"'' activation
           && !lib.hasInfix "/compat/env-secret-file-marker" activation
           && !lib.hasInfix "ENV_SECRET_VARIABLE_MARKER" activation;
    }

    {
      name = "URL env failures exit before atomic config replacement";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable = true;
            inspr.paimos-cli.defaultInstance = "work";
            inspr.paimos-cli.instances.work = urlEnvInstance;
          };
        };
        activation = activationData r;
        preMove = beforeAtomicMove activation;
        in r.success
           && lib.hasInfix "is set but empty" preMove
           && lib.hasInfix "not set after sourcing" preMove
           && lib.hasInfix "not found" preMove
           && lib.hasInfix "refusing to replace config" preMove
           && lib.length (lib.splitString "exit 1" preMove) >= 4
           && lib.hasInfix ''mv -f "$tmp" "$CONFIG_FILE"'' activation;
    }

    {
      name = "legacy api_key guard runs before temp creation and replacement";
      assertion =
        let
          r = evalEnabled validInstance;
          activation = activationData r;
          preTemp = beforeTempCreation activation;
        in r.success
           && lib.hasInfix "/bin/yq" preTemp
           && lib.hasInfix ''has("api_key")'' preTemp
           && lib.hasInfix "paimos auth whoami" preTemp
           && lib.hasInfix "paimos auth login" preTemp
           && lib.hasInfix "exit 1" preTemp
           && lib.hasInfix "tmp=\"$(mktemp" activation
           && lib.hasInfix ''mv -f "$tmp" "$CONFIG_FILE"'' activation;
    }

    {
      name = "instance with literal and env URL sources triggers XOR assertion";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable = true;
            inspr.paimos-cli.defaultInstance = "conflict";
            inspr.paimos-cli.instances.conflict = {
              url = "https://paimos.example.com";
              urlEnvFile = "/routing/url-file-marker";
              urlVar = "ROUTING_URL_MARKER";
            };
          };
        };
        in r.success
           && lib.any (a: lib.hasInfix "exactly ONE of" a.message)
                      r.failedAssertions;
    }

    {
      name = "URL env file without variable triggers assertion";
      assertion =
        let r = evalModule {
          module = paimosConfig;
          config = {
            inspr.paimos-cli.enable = true;
            inspr.paimos-cli.defaultInstance = "incomplete";
            inspr.paimos-cli.instances.incomplete.urlEnvFile =
              "/routing/url-file-marker";
          };
        };
        in r.success
           && lib.any (a: lib.hasInfix "urlVar is null" a.message)
                      r.failedAssertions;
    }

    {
      name = "URL env variable rejects option-like and shell-active names";
      assertion =
        lib.all (invalidUrlVar:
          let r = evalModule {
            module = paimosConfig;
            config = {
              inspr.paimos-cli.enable = true;
              inspr.paimos-cli.defaultInstance = "invalid";
              inspr.paimos-cli.instances.invalid = {
                urlEnvFile = "/routing/url-file-marker";
                urlVar = invalidUrlVar;
              };
            };
          };
          in r.success
             && lib.any (a: lib.hasInfix "valid shell environment" a.message)
                        r.failedAssertions
        ) [
          "--null"
          ''ROUTE"; $(touch /tmp/urlvar-injected); #''
          "9INVALID"
        ];
    }

    {
      name = "deprecated API key compatibility options remain accepted with warning";
      assertion =
        let r = evalEnabled compatibilityInstance;
        in r.success
           && r.failedAssertions == [ ]
           && lib.length r.warnings == 1
           && lib.hasInfix "deprecated compatibility options"
                          (builtins.head r.warnings)
           && lib.hasInfix "ignored" (builtins.head r.warnings)
           && !lib.hasInfix "/compat/secret-file-marker"
                           (builtins.head r.warnings)
           && !lib.hasInfix "SECRET_VARIABLE_MARKER"
                           (builtins.head r.warnings);
    }

    {
      name = "deprecated secret file and variable values never enter activation";
      assertion =
        let
          r = evalEnabled compatibilityInstance;
          activation = activationData r;
        in r.success
           && !lib.hasInfix "/compat/secret-file-marker" activation
           && !lib.hasInfix "SECRET_VARIABLE_MARKER" activation;
    }

    {
      name = "rendered activation contains no API credential field or lookup";
      assertion =
        let
          r = evalEnabled compatibilityInstance;
          activation = activationData r;
        in r.success
           && !lib.hasInfix "api_key:" activation
           && !lib.hasInfix "PAIMOS_API_KEY" activation
           && !lib.hasInfix "key_value" activation
           && !lib.hasInfix "/compat/secret-file-marker" activation
           && !lib.hasInfix "SECRET_VARIABLE_MARKER" activation;
    }

    {
      name = "routing values are YAML-escaped before rendering";
      assertion =
        let
          r = evalModule {
            module = paimosConfig;
            config = {
              inspr.paimos-cli.enable = true;
              inspr.paimos-cli.defaultInstance = "team\"s";
              inspr.paimos-cli.instances."team\"s".url =
                "https://paimos.example.com/team\"s";
            };
          };
          activation = activationData r;
        in r.success
           && r.failedAssertions == [ ]
           && lib.hasInfix ''default_instance: "team\"s"'' activation
           && lib.hasInfix ''"team\"s":'' activation
           && lib.hasInfix ''url: "https://paimos.example.com/team\"s"''
                          activation;
    }
  ];
in
  runTests "paimos-config" tests
