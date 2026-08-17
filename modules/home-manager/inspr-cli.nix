# inspr-modules/modules/home-manager/inspr-cli.nix
#
# Render the `inspr` CLI's fleet configuration declaratively.
#
# The CLI ships with every fleet endpoint EMPTY, because it is a public library
# and whose Headscale or tracker you run is yours to say. Checks that need an
# unset value report SKIP rather than FAIL. This module is how a studio flake
# supplies its own values — the same atelier/studio split the rest of the
# repository uses: parameterised primitive here, values in your config.
#
# Usage:
#   imports = [ inputs.inspr-modules.homeManagerModules.inspr-cli ];
#   inspr.cli.fleet = {
#     headscaleUrl = "https://headscale.example.org";
#     tailnetName  = "headscale.example.org";
#     paimosUrl    = "https://tracker.example.org";
#     paimosInstance = "main";
#     pharosHost   = "manifest-host";
#     exampleHost  = "web1";
#   };
#
# Nothing here is a credential. Every value is an endpoint or a name, and the
# rendered file is world-readable. Auth lives in the OS keyring.
{ config, lib, ... }:
let
  cfg = config.inspr.cli;
  f = cfg.fleet;
  line = name: value: lib.optionalString (value != null && value != "") ''${name}="${value}"'';
in
{
  options.inspr.cli = {
    enable = lib.mkEnableOption "declarative fleet config for the inspr CLI";

    fleet = {
      headscaleUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://headscale.example.org";
        description = ''
          Headscale SERVICE url, not the host it runs on. Enables the
          `headscale_reachable` check.
        '';
      };
      tailnetName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "headscale.example.org";
        description = ''
          Expected tailnet name. Enables `tailscale_control_url`, which is the
          only check that distinguishes your Headscale from Tailscale SaaS — a
          host pointed at the wrong control server passes every other check.
        '';
      };
      paimosUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://tracker.example.org";
        description = "Paimos instance url, shown in onboarding instructions.";
      };
      paimosInstance = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "main";
        description = "Local instance alias used by `paimos auth login --name`.";
      };
      pharosHost = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "manifest-host";
        description = ''
          Host whose checkout holds generated Pharos manifests. Used by
          `inspr post-deploy`; the comparison is skipped when unset.
        '';
      };
      exampleHost = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "web1";
        description = "Host slug shown in `inspr --help`. Cosmetic only.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."inspr/fleet.conf".text = ''
      # Rendered by inspr-modules homeManagerModules.inspr-cli — do not edit.
      # Change the values in your Home Manager configuration instead.
    '' + lib.concatStringsSep "\n" (lib.filter (l: l != "") [
      (line "INSPR_HEADSCALE_URL" f.headscaleUrl)
      (line "INSPR_TAILNET_NAME" f.tailnetName)
      (line "INSPR_PAIMOS_URL" f.paimosUrl)
      (line "INSPR_PAIMOS_INSTANCE" f.paimosInstance)
      (line "INSPR_PHAROS_HOST" f.pharosHost)
      (line "INSPR_EXAMPLE_HOST" f.exampleHost)
    ]) + "\n";
  };
}
