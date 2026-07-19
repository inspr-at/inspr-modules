# inspr — bash CLI packaged as a nix derivation.
#
# The agent-ready operating layer's diagnostic + heal + onboard tool.
# Replaces the older `inspr-doctor.sh` (single-purpose probe) with a
# fuller sub-command CLI: check / heal / onboard, plus --vision and
# --help flags. See VISION.md (`inspr --vision`) for the mission.
#
# Packaging note: identical pattern to ./secrets-audit (writeShellApplication
# with shellcheck at build time + automatic-minimum dependency closure).
# bashOptions explicitly excludes `errexit` because the script deliberately
# continues past individual check failures (each check returns its own code).
#
{
  lib,
  writeShellApplication,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  git,
  jq,
  yq-go,
  curl,
  openssh,
}:

writeShellApplication {
  name = "inspr";

  runtimeInputs = [
    coreutils  # stat, basename, wc, tr, etc.
    findutils  # find
    gnugrep
    gnused
    git        # submodule status / git rev-parse
    jq         # tailscale --json parsing
    yq-go      # structural, non-printing Paimos config validation
    curl       # headscale /health probe
    openssh    # optional live-host deployment checks
  ];

  # The script deliberately uses `set -uo pipefail` WITHOUT `-e`. Each
  # check runs in a subshell and returns 0=pass, 1=fail, 77=skip; the
  # main flow needs to continue past failures and tally them. Adding
  # `-e` would cause the first non-zero return to abort the whole run.
  bashOptions = [
    "nounset"
    "pipefail"
  ];

  # Shellcheck excludes (all false positives in this context):
  # SC1091: source ./*.env inside conditional subshell — shellcheck can't
  #         follow runtime-conditional sources; behavior is correct.
  # SC2016: single-quoted jq programs intentionally keep jq variables intact.
  # SC2001: sed per-line prepend — same false positive as secrets-audit.
  # SC2059: printf format-string variables — variables ARE color codes
  #         (${GREEN}, ${RED}, etc.), not user-controlled data.
  # SC2088: literal ~ in run_check description strings (display text only;
  #         the actual paths come from $HOME-resolved $NIXCFG_DIR etc.).
  # SC2029: post-deploy expands a validated host slug into a remote manifest path.
  # SC2155: local var=$(cmd) — exit-code masking acceptable in our context.
  # SC2329: heal_fix_* functions ARE invoked, indirectly via $fix_fn lookup
  #         in cmd_heal's loop. Shellcheck can't see indirect dispatch.
  excludeShellChecks = [
    "SC1091"
    "SC2016"
    "SC2001"
    "SC2059"
    "SC2088"
    "SC2029"
    "SC2155"
    "SC2329"
  ];

  text = builtins.readFile ./inspr.sh;

  meta = {
    description = "INSPR onboarding + drift-heal CLI (check / heal / onboard / --vision)";
    homepage = "https://github.com/markus-barta/inspr-modules";
    license = lib.licenses.agpl3Only;
    mainProgram = "inspr";
  };
}
