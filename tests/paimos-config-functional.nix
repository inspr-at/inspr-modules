{ pkgs }:

let
  inherit (pkgs) lib;

  harness = import ./module-eval/harness.nix { inherit lib pkgs; };

  activationFor =
    {
      defaultInstance,
      instances,
    }:
    let
      result = harness.evalModule {
        module = ../modules/home-manager/paimos-config.nix;
        config = {
          home.homeDirectory = "$PAIMOS_TEST_ROOT/home";
          inspr.paimos-cli = {
            enable = true;
            inherit defaultInstance instances;
          };
        };
      };
    in
    if !result.success || result.failedAssertions != [ ] then
      throw "paimos-config functional fixture failed module evaluation"
    else
      result.config.home.activation.bootstrapPaimosConfig.data;

  routeName = "work \"quoted\" $(touch \"$PAIMOS_TEST_ROOT/name-injected\")";
  missingRouteFile = "/definitely-missing/$(touch \"$PAIMOS_TEST_ROOT/path-injected\")";
  routingUrl = "https://example.invalid/first\r\nsecond\"quoted\"'single'\\backslash";

  routingEnv = pkgs.writeText "paimos-routing-url.env" ''
    ROUTING_URL=${lib.escapeShellArg routingUrl}
  '';
  unsetRoutingEnv = pkgs.writeText "paimos-routing-unset.env" ''
    # ROUTING_URL intentionally absent
  '';
  emptyRoutingEnv = pkgs.writeText "paimos-routing-empty.env" ''
    ROUTING_URL=
  '';

  literalActivation = activationFor {
    defaultInstance = routeName;
    instances.${routeName}.url = "https://replacement.example.invalid";
  };
  missingActivation = activationFor {
    defaultInstance = routeName;
    instances.${routeName} = {
      urlEnvFile = missingRouteFile;
      urlVar = "ROUTING_URL";
    };
  };
  unsetActivation = activationFor {
    defaultInstance = routeName;
    instances.${routeName} = {
      urlEnvFile = toString unsetRoutingEnv;
      urlVar = "ROUTING_URL_UNSET";
    };
  };
  emptyActivation = activationFor {
    defaultInstance = routeName;
    instances.${routeName} = {
      urlEnvFile = toString emptyRoutingEnv;
      urlVar = "ROUTING_URL";
    };
  };
  validActivation = activationFor {
    defaultInstance = routeName;
    instances.${routeName} = {
      urlEnvFile = toString routingEnv;
      urlVar = "ROUTING_URL";
    };
  };

  literalScript = pkgs.writeText "paimos-literal-activation.sh" literalActivation;
  missingScript = pkgs.writeText "paimos-missing-url-activation.sh" missingActivation;
  unsetScript = pkgs.writeText "paimos-unset-url-activation.sh" unsetActivation;
  emptyScript = pkgs.writeText "paimos-empty-url-activation.sh" emptyActivation;
  validScript = pkgs.writeText "paimos-valid-url-activation.sh" validActivation;

  legacyConfig = pkgs.writeText "paimos-legacy-config.yaml" ''
    default_instance: "legacy"
    instances:
      "legacy":
        url: "https://legacy.example.invalid"
        api_key: "synthetic-regression-marker"
  '';
  preservedConfig = pkgs.writeText "paimos-preserved-config.yaml" ''
    default_instance: "preserved"
    instances:
      "preserved":
        url: "https://preserved.example.invalid"
  '';
  expectedConfig = pkgs.writeText "paimos-expected-config.yaml" (
    "default_instance: ${builtins.toJSON routeName}\n"
    + "instances:\n"
    + "  ${builtins.toJSON routeName}:\n"
    + "    url: ${builtins.toJSON routingUrl}\n"
  );
in
pkgs.runCommand "paimos-config-functional-tests"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail

    export PAIMOS_TEST_ROOT="$PWD/paimos-functional"
    mkdir -p "$PAIMOS_TEST_ROOT/home/.paimos"
    config_file="$PAIMOS_TEST_ROOT/home/.paimos/config.yaml"
    before_file="$PAIMOS_TEST_ROOT/before.yaml"

    install -m 0600 ${legacyConfig} "$config_file"
    cp "$config_file" "$before_file"
    if bash ${literalScript} >"$PAIMOS_TEST_ROOT/legacy.log" 2>&1; then
      printf '%s\n' 'legacy api_key config was unexpectedly replaced' >&2
      exit 1
    fi
    cmp "$before_file" "$config_file"
    if grep -Fq 'synthetic-regression-marker' "$PAIMOS_TEST_ROOT/legacy.log"; then
      printf '%s\n' 'legacy structural guard exposed a credential value' >&2
      exit 1
    fi

    install -m 0600 ${preservedConfig} "$config_file"
    cp "$config_file" "$before_file"
    if bash ${missingScript} >"$PAIMOS_TEST_ROOT/missing.log" 2>&1; then
      printf '%s\n' 'missing URL file unexpectedly succeeded' >&2
      exit 1
    fi
    cmp "$before_file" "$config_file"

    if bash ${unsetScript} >"$PAIMOS_TEST_ROOT/unset.log" 2>&1; then
      printf '%s\n' 'unset URL variable unexpectedly succeeded' >&2
      exit 1
    fi
    cmp "$before_file" "$config_file"

    if bash ${emptyScript} >"$PAIMOS_TEST_ROOT/empty.log" 2>&1; then
      printf '%s\n' 'empty URL variable unexpectedly succeeded' >&2
      exit 1
    fi
    cmp "$before_file" "$config_file"

    bash ${validScript}
    cmp ${expectedConfig} "$config_file"

    for injected in name-injected path-injected; do
      if [[ -e "$PAIMOS_TEST_ROOT/$injected" ]]; then
        printf '%s\n' "shell interpolation created $injected" >&2
        exit 1
      fi
    done

    touch "$out"
  ''
