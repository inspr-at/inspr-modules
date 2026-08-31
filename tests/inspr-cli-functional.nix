# Execute a rendered fleet.conf with Bash, matching the inspr CLI's source-time
# behavior. Synthetic shell-active strings must remain byte-for-byte values and
# must never execute while the file is sourced.
{ pkgs }:

let
  harness = import ./module-eval/harness.nix {
    inherit pkgs;
    inherit (pkgs) lib;
  };

  evaluate = fleet:
    harness.evalModule {
      module = ../modules/home-manager/inspr-cli.nix;
      config.inspr.cli = {
        enable = true;
        inherit fleet;
      };
    };

  renderedConfig = (evaluate {
    headscaleUrl = "double\"quote";
    tailnetName = "single'quote";
    paimosUrl = "$(touch \"$TMPDIR/inspr-command-substitution-ran\")";
    paimosInstance = "`touch \"$TMPDIR/inspr-backtick-ran\"`";
    pharosUrl = "C:\\fleet\\path\\$HOME";
    pharosHost = "two words";
    gitIdentityName = "line one\nline two";
    gitIdentityEmail = "$HOME@example.invalid";
    exampleHost = "plain-value";
  }).config.xdg.configFile."inspr/fleet.conf".text;

  emptyConfig = (evaluate {
    headscaleUrl = null;
    tailnetName = "";
    paimosUrl = null;
    paimosInstance = "";
    pharosUrl = null;
    pharosHost = "";
    gitIdentityName = null;
    gitIdentityEmail = "";
    exampleHost = null;
  }).config.xdg.configFile."inspr/fleet.conf".text;

  fleetConf = pkgs.writeText "fleet.conf" renderedConfig;
  emptyFleetConf = pkgs.writeText "fleet-empty.conf" emptyConfig;
in
pkgs.runCommand "inspr-cli-functional"
  {
    nativeBuildInputs = [ pkgs.bash ];
  }
  ''
    set -eu

    assert_eq() {
      if [ "$1" != "$2" ]; then
        echo "fleet.conf source-time value mismatch: $3" >&2
        exit 1
      fi
    }

    test ! -e "$TMPDIR/inspr-command-substitution-ran"
    test ! -e "$TMPDIR/inspr-backtick-ran"

    # shellcheck source=/dev/null
    . ${fleetConf}

    test ! -e "$TMPDIR/inspr-command-substitution-ran"
    test ! -e "$TMPDIR/inspr-backtick-ran"
    assert_eq "$INSPR_HEADSCALE_URL" 'double"quote' "double quote"
    assert_eq "$INSPR_TAILNET_NAME" "single'quote" "single quote"
    assert_eq "$INSPR_PAIMOS_URL" '$(touch "$TMPDIR/inspr-command-substitution-ran")' "command substitution"
    assert_eq "$INSPR_PAIMOS_INSTANCE" '`touch "$TMPDIR/inspr-backtick-ran"`' "backticks"
    assert_eq "$INSPR_PHAROS_URL" 'C:\fleet\path\$HOME' "backslashes"
    assert_eq "$INSPR_PHAROS_HOST" 'two words' "spaces"
    expected_multiline='line one
line two'
    assert_eq "$INSPR_GIT_IDENTITY_NAME" "$expected_multiline" "newlines"
    assert_eq "$INSPR_GIT_IDENTITY_EMAIL" '$HOME@example.invalid' "dollar expansion"
    assert_eq "$INSPR_EXAMPLE_HOST" 'plain-value' "ordinary value"

    INSPR_EXAMPLE_HOST=preserved
    # shellcheck source=/dev/null
    . ${emptyFleetConf}
    assert_eq "$INSPR_EXAMPLE_HOST" preserved "value-free config"

    touch "$out"
  ''
