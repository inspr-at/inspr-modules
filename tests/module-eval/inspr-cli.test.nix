# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/inspr-cli.test.nix
#
# Evaluation tests for the declarative inspr fleet.conf renderer. The file is
# sourced by the Bash CLI, so configured strings must render as inert shell
# words while null and empty values remain absent.
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  insprCli = ../../modules/home-manager/inspr-cli.nix;

  evaluate = fleet:
    evalModule {
      module = insprCli;
      config = {
        inspr.cli = {
          enable = true;
          inherit fleet;
        };
      };
    };

  renderedLines = fleet:
    let
      result = evaluate fleet;
      text = result.config.xdg.configFile."inspr/fleet.conf".text;
    in
    lib.filter (line: lib.hasPrefix "INSPR_" line) (lib.splitString "\n" text);

  renderedText = fleet:
    (evaluate fleet).config.xdg.configFile."inspr/fleet.conf".text;

  assignment = name: value: "${name}=${lib.escapeShellArg value}";

  shellCases = [
    {
      name = "single quotes are shell-escaped";
      value = "single'quote";
    }
    {
      name = "double quotes are shell-escaped";
      value = "double\"quote";
    }
    {
      name = "command substitution is shell-escaped";
      value = "$(touch command-substitution-marker)";
    }
    {
      name = "backticks are shell-escaped";
      value = "`touch backtick-marker`";
    }
    {
      name = "backslashes are shell-escaped";
      value = "C:\\fleet\\path\\$HOME";
    }
    {
      name = "spaces are shell-escaped";
      value = "two words";
    }
    {
      name = "newlines are shell-escaped";
      value = "line one\nline two";
    }
  ];

  safetyTests = map (testCase: {
    inherit (testCase) name;
    assertion =
      let
        text = renderedText { exampleHost = testCase.value; };
      in
      lib.hasSuffix "${assignment "INSPR_EXAMPLE_HOST" testCase.value}\n" text
      && lib.length (lib.filter
        (line: lib.hasPrefix "INSPR_" line)
        (lib.splitString "\n" text)) == 1;
  }) shellCases;

  tests = [
    {
      name = "disabled module emits no fleet config";
      assertion =
        let
          result = evalModule {
            module = insprCli;
            config = { };
          };
        in
        result.success && (result.config.xdg.configFile or { }) == { };
    }

    {
      name = "null and empty values emit no assignments";
      assertion =
        let
          result = evaluate {
            headscaleUrl = null;
            tailnetName = "";
            paimosUrl = null;
            paimosInstance = "";
            pharosUrl = null;
            pharosHost = "";
            gitIdentityName = null;
            gitIdentityEmail = "";
            exampleHost = null;
          };
        in
        result.success && renderedLines result.config.inspr.cli.fleet == [ ];
    }

    {
      name = "ordinary values retain the complete variable mapping";
      assertion =
        renderedLines {
          headscaleUrl = "headscale";
          tailnetName = "tailnet";
          paimosUrl = "paimos";
          paimosInstance = "instance";
          pharosUrl = "pharos-url";
          pharosHost = "pharos-host";
          gitIdentityName = "identity-name";
          gitIdentityEmail = "identity-email";
          exampleHost = "example-host";
        }
        == [
          (assignment "INSPR_HEADSCALE_URL" "headscale")
          (assignment "INSPR_TAILNET_NAME" "tailnet")
          (assignment "INSPR_PAIMOS_URL" "paimos")
          (assignment "INSPR_PAIMOS_INSTANCE" "instance")
          (assignment "INSPR_PHAROS_URL" "pharos-url")
          (assignment "INSPR_PHAROS_HOST" "pharos-host")
          (assignment "INSPR_GIT_IDENTITY_NAME" "identity-name")
          (assignment "INSPR_GIT_IDENTITY_EMAIL" "identity-email")
          (assignment "INSPR_EXAMPLE_HOST" "example-host")
        ];
    }
  ] ++ safetyTests;
in
runTests "inspr-cli" tests
