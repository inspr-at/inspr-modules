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
    nixcfgDir = "/tmp/host config'quote";
    insprDir = "/tmp/umbrella checkout";
    nixcfgRepoUrl = "https://git.example.org/you/host-config.git";
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
    nixcfgDir = null;
    insprDir = null;
    nixcfgRepoUrl = null;
  }).config.xdg.configFile."inspr/fleet.conf".text;

  fleetConf = pkgs.writeText "fleet.conf" renderedConfig;
  emptyFleetConf = pkgs.writeText "fleet-empty.conf" emptyConfig;
in
pkgs.runCommand "inspr-cli-functional"
  {
    nativeBuildInputs = [ pkgs.bash pkgs.gnused pkgs.gnugrep pkgs.coreutils ];
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
    assert_eq "$INSPR_NIXCFG_DIR" "/tmp/host config'quote" "host-config checkout"
    assert_eq "$INSPR_DIR" '/tmp/umbrella checkout' "umbrella checkout"
    assert_eq "$INSPR_NIXCFG_REPO_URL" 'https://git.example.org/you/host-config.git' "clone URL"

    INSPR_EXAMPLE_HOST=preserved
    # shellcheck source=/dev/null
    . ${emptyFleetConf}
    assert_eq "$INSPR_EXAMPLE_HOST" preserved "value-free config"

    # Load the real CLI definitions without dispatching unrelated auth/network
    # diagnostics. Exercise run_check's 77 -> SKIP contract with no repositories.
    sed '/^# ── main dispatch/,$d' ${../pkgs/inspr/inspr.sh} > cli-functions.sh
    (
      unset INSPR_NIXCFG_DIR INSPR_DIR INSPR_NIXCFG_REPO_URL
      export HOME="$TMPDIR/empty-home" INSPR_FLEET_CONF=${emptyFleetConf}
      mkdir -p "$HOME"
      . ./cli-functions.sh
      set -e
      PROFILE=workstation
      run_check workstation repo_nixcfg 'host-config checkout' unused > nixcfg-result || exit 1
      run_check workstation repo_inspr 'umbrella checkout' unused > inspr-result || exit 1
      assert_eq "$SKIP" 2 'unset repository checks SKIP'
      assert_eq "$FAIL" 0 'unset repository checks never FAIL'
      grep -F '[skipped]' nixcfg-result
      grep -F 'INSPR_NIXCFG_DIR not set (fleet.conf or inspr.cli.fleet.nixcfgDir)' nixcfg-result
      grep -F 'INSPR_DIR not set (fleet.conf or inspr.cli.fleet.insprDir)' inspr-result
    )
    (
      unset INSPR_NIXCFG_DIR INSPR_DIR INSPR_NIXCFG_REPO_URL
      export INSPR_FLEET_CONF=${fleetConf}
      . ./cli-functions.sh
      set -e
      assert_eq "$NIXCFG_DIR" "/tmp/host config'quote" 'fleet.conf precedes path assignments'
      assert_eq "$INSPR_DIR" '/tmp/umbrella checkout' 'fleet.conf umbrella path'
      assert_eq "$INSPR_NIXCFG_REPO_URL" 'https://git.example.org/you/host-config.git' 'fleet.conf clone URL'
    )

    touch "$out"
  ''
