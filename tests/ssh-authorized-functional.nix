# ─────────────────────────────────────────────────────────────────────────
# tests/ssh-authorized-functional.nix
#
# Executes the rendered insprSshAuthorized activation against synthetic
# authorized_keys files (INSPR-261). The module-eval suite covers option
# shapes and eval-time throws; THIS suite covers the awk splice — the most
# intricate shell in the repo — which had no functional coverage:
#
#   1. fresh host: no authorized_keys → managed block written, mode 0600
#   2. valid markers: block replaced in place; manual lines above AND
#      below the block preserved byte-exactly
#   3. begin marker without end marker: activation FAILS non-zero and the
#      original file is untouched (pre-fix behavior silently discarded
#      everything below the begin marker — including recovery keys)
#   4. marker text as substring (not an exact line): nothing truncated —
#      existing content preserved, managed block appended
#
# SPDX-License-Identifier: AGPL-3.0-only
# ─────────────────────────────────────────────────────────────────────────
{ pkgs }:

let
  inherit (pkgs) lib;

  harness = import ./module-eval/harness.nix { inherit lib pkgs; };

  markerBegin = "# >>> inspr.ssh.authorized BEGIN — declaratively managed, do not edit between markers";
  markerEnd = "# <<< inspr.ssh.authorized END";

  evalResult = harness.evalModule {
    module = ../modules/home-manager/ssh-authorized.nix;
    config = {
      inspr.ssh.authorized.enable = true;
      inspr.ssh.authorized.keys."test@functional" =
        "ssh-ed25519 AAAAFunctionalTestKey0000 test@functional";
      inspr.ssh.authorized.trust = [ "test@functional" ];
    };
  };

  activation =
    if !evalResult.success || evalResult.failedAssertions != [ ] then
      throw "ssh-authorized functional fixture failed module evaluation"
    else
      evalResult.config.home.activation.insprSshAuthorized.data;

  activationScript = pkgs.writeText "ssh-authorized-activation.sh" activation;

  manualAbove = "ssh-ed25519 AAAAManualHeadscaleKey headscale-deploy";
  manualBelow = "ssh-ed25519 AAAARecoveryKey0000 break-glass-recovery";

  validMarkers = pkgs.writeText "auth-valid-markers" ''
    ${manualAbove}
    ${markerBegin}
    ssh-ed25519 AAAAStaleManagedKey old@managed
    ${markerEnd}
    ${manualBelow}
  '';

  beginWithoutEnd = pkgs.writeText "auth-begin-no-end" ''
    ${manualAbove}
    ${markerBegin}
    ssh-ed25519 AAAAStaleManagedKey old@managed
    ${manualBelow}
  '';

  substringMarker = pkgs.writeText "auth-substring-marker" ''
    ${manualAbove}
    # commented-out copy: ${markerBegin}
    ${manualBelow}
  '';
in
pkgs.runCommand "ssh-authorized-functional-tests"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    set -euo pipefail

    export HOME="$PWD/synthetic-home"

    reset_home() {
      rm -rf "$HOME"
      mkdir -p "$HOME/.ssh"
      chmod 0700 "$HOME/.ssh"
    }
    AUTH="$HOME/.ssh/authorized_keys"

    # ── 1. fresh host: block written, strict mode ─────────────────────────
    reset_home
    bash ${activationScript}
    grep -Fxq ${lib.escapeShellArg markerBegin} "$AUTH"
    grep -Fxq ${lib.escapeShellArg markerEnd} "$AUTH"
    grep -Fq "test@functional" "$AUTH"
    [ "$(stat -c %a "$AUTH")" = "600" ]

    # ── 2. valid markers: replace block, preserve manual lines ────────────
    reset_home
    install -m 0600 ${validMarkers} "$AUTH"
    bash ${activationScript}
    grep -Fxq ${lib.escapeShellArg manualAbove} "$AUTH"
    grep -Fxq ${lib.escapeShellArg manualBelow} "$AUTH"
    grep -Fq "test@functional" "$AUTH"
    if grep -Fq "old@managed" "$AUTH"; then
      printf '%s\n' 'stale managed key survived the splice' >&2
      exit 1
    fi

    # ── 3. begin without end: fail loudly, original untouched ─────────────
    reset_home
    install -m 0600 ${beginWithoutEnd} "$AUTH"
    cp "$AUTH" "$HOME/before"
    if bash ${activationScript} > "$HOME/no-end.log" 2>&1; then
      printf '%s\n' 'missing end marker unexpectedly succeeded' >&2
      exit 1
    fi
    cmp "$HOME/before" "$AUTH"
    grep -Fq "end marker is missing" "$HOME/no-end.log"
    if ! grep -Fxq ${lib.escapeShellArg manualBelow} "$AUTH"; then
      printf '%s\n' 'recovery key below the block was lost' >&2
      exit 1
    fi

    # ── 4. substring marker: no truncation, block appended ────────────────
    reset_home
    install -m 0600 ${substringMarker} "$AUTH"
    bash ${activationScript}
    grep -Fxq ${lib.escapeShellArg manualAbove} "$AUTH"
    grep -Fxq ${lib.escapeShellArg manualBelow} "$AUTH"
    grep -Fq "test@functional" "$AUTH"

    touch "$out"
  ''
