# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║                 INSPR — Declarative Paimos routing                          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Materialize only Paimos instance routing in ~/.paimos/config.yaml:
# default_instance plus each instance URL. A URL may be a Nix literal or come
# from a trusted KEY=value env file; neither path handles credentials.
#
# INSPR workstation authentication policy is interactive. After activation,
# run `paimos auth login --url ... --name ...` and enter the API key at the
# hidden prompt; Paimos stores that credential in the OS keyring. Headless
# automation may inject PAIMOS_URL + PAIMOS_API_KEY into the process from
# approved encrypted storage, but this module never reads, renders, or persists
# credential values.
#
# Compatibility window (INSPR-225): apiKeyEnvFile and apiKeyVar remain accepted
# for one release so existing consumers still evaluate. They are ignored and
# emit a warning. Remove them from consumer configuration.
#
# Usage (consumer's home.nix):
#   imports = [ inputs.inspr-modules.homeManagerModules.paimos-config ];
#   inspr.paimos-cli = {
#     enable = true;
#     defaultInstance = "mine";
#     instances.mine.url = "https://your-paimos.example.com";
#   };
#
# Per instance, exactly one of {url, urlEnvFile} must be set. urlEnvFile
# requires urlVar.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.inspr.paimos-cli;

  # JSON strings are valid YAML scalars and give Nix-known values complete
  # escaping without depending on a YAML library.
  yamlQuote = builtins.toJSON;

  mkInstanceFragment = name: inst:
    if inst.url != null then
      let
        nestedBlock = "  ${yamlQuote name}:\n    url: ${yamlQuote inst.url}";
      in
      ''
        printf '%s\n' ${lib.escapeShellArg nestedBlock}
      ''
    else
      ''
        if [[ -f ${lib.escapeShellArg inst.urlEnvFile} ]]; then
          (
            set -a
            # shellcheck disable=SC1090
            source ${lib.escapeShellArg inst.urlEnvFile}
            set +a

            if url_value="$(${pkgs.coreutils}/bin/printenv -- ${lib.escapeShellArg inst.urlVar})"; then
              if [[ -z "$url_value" ]]; then
                printf '%s\n' ${lib.escapeShellArg "paimos-config: ERROR ${name}: ${inst.urlVar} is set but empty in ${inst.urlEnvFile}; refusing to replace config"} >&2
                exit 1
              fi
            else
              printf '%s\n' ${lib.escapeShellArg "paimos-config: ERROR ${name}: ${inst.urlVar} not set after sourcing ${inst.urlEnvFile}; refusing to replace config"} >&2
              exit 1
            fi

            # JSON strings are valid YAML scalars. jq safely encodes quotes,
            # backslashes, CR/LF, and other control characters in the
            # runtime-provided URL.
            url_encoded=$(${pkgs.jq}/bin/jq -Rn --arg value "$url_value" '$value')
            printf '%s\n' ${lib.escapeShellArg "  ${yamlQuote name}:"}
            printf '    url: %s\n' "$url_encoded"
          )
        else
          printf '%s\n' ${lib.escapeShellArg "paimos-config: ERROR ${name}: ${inst.urlEnvFile} not found; refusing to replace config"} >&2
          exit 1
        fi
      '';

  # Assertions do not short-circuit evaluation. Filter malformed instances out
  # of the renderer so assertion messages surface instead of null coercion
  # errors from the activation string.
  wellFormedInstances = lib.filterAttrs (_: inst:
    ((inst.url != null) != (inst.urlEnvFile != null))
    && (inst.urlEnvFile == null || inst.urlVar != null)
    && (inst.urlVar == null || builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" inst.urlVar != null)
  ) cfg.instances;

  instanceFragments = lib.concatStringsSep "\n" (
    lib.mapAttrsToList mkInstanceFragment wellFormedInstances
  );

  deprecatedCredentialWarnings = lib.concatLists (
    lib.mapAttrsToList (name: inst:
      lib.optional (inst.apiKeyEnvFile != null || inst.apiKeyVar != null) ''
        inspr.paimos-cli.instances.${name}: apiKeyEnvFile/apiKeyVar are
        deprecated compatibility options and are ignored. This module now
        writes routing only. Compatibility is evaluation-only: before any new
        login, an existing config containing legacy api_key must be migrated by
        Paimos 4.8 with all auth overrides unset. After that, remove these
        options and authenticate interactively with `paimos auth login` if
        needed.
        These options will be removed after this compatibility release.
      ''
    ) cfg.instances
  );
in
{
  options.inspr.paimos-cli = {
    enable = lib.mkEnableOption "declarative Paimos instance routing without credentials";

    defaultInstance = lib.mkOption {
      type = lib.types.str;
      description = ''
        Which configured instance becomes the default for `paimos` CLI
        invocations that do not pass `--instance`. Must be a key in `instances`.
      '';
      example = "mine";
    };

    instances = lib.mkOption {
      description = ''
        Named Paimos instances to materialize into ~/.paimos/config.yaml.
        Each instance provides either a literal URL or urlEnvFile + urlVar for
        a URL stored outside Nix. Workstation credentials belong in the OS
        keyring after interactive `paimos auth login`; headless credentials are
        runtime inputs.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Paimos instance URL as a Nix string. Mutually exclusive with
                urlEnvFile; exactly one must be set.
              '';
              example = "https://your-paimos.example.com";
            };

            urlEnvFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Absolute path to a trusted KEY=value env file containing the
                instance URL. Requires urlVar and is mutually exclusive with
                url. This is routing input, not credential input.
              '';
              example = "/run/agenix/your-paimos-url";
            };

            urlVar = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Variable name inside urlEnvFile holding the instance URL.
                Required with urlEnvFile; ignored with a literal url.
              '';
              example = "PAIMOS_URL";
            };

            apiKeyEnvFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              visible = false;
              description = ''
                Deprecated compatibility option. Ignored; no file is read.
                Before any new login, let Paimos 4.8 migrate an existing legacy
                config with all auth overrides unset. Then remove this option.
              '';
            };

            apiKeyVar = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              visible = false;
              description = ''
                Deprecated compatibility option. Ignored; no variable is read.
                Before any new login, let Paimos 4.8 migrate an existing legacy
                config with all auth overrides unset. Then remove this option.
              '';
            };
          };
        }
      );
      default = { };
      defaultText = lib.literalExpression "{ }";
      example = lib.literalExpression ''
        {
          mine.url = "https://your-paimos.example.com";
          work = {
            urlEnvFile = "/run/agenix/work-paimos-url";
            urlVar = "WORK_PAIMOS_URL";
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (lib.attrNames cfg.instances) != [ ];
        message = ''
          inspr.paimos-cli.enable = true requires at least one entry in
          inspr.paimos-cli.instances. See `inspr.paimos-cli.instances`
          for the expected shape.
        '';
      }
      {
        assertion = lib.elem cfg.defaultInstance (lib.attrNames cfg.instances);
        message = ''
          inspr.paimos-cli.defaultInstance = "${cfg.defaultInstance}" must be a key
          in inspr.paimos-cli.instances.
          Declared instances: ${toString (lib.attrNames cfg.instances)}.
        '';
      }
    ]
    ++ lib.concatLists (lib.mapAttrsToList (name: inst: [
      {
        assertion = (inst.url != null) != (inst.urlEnvFile != null);
        message = ''
          inspr.paimos-cli.instances."${name}": exactly ONE of
          {url, urlEnvFile} must be set.
        '';
      }
      {
        assertion = inst.urlEnvFile == null || inst.urlVar != null;
        message = ''
          inspr.paimos-cli.instances."${name}": urlEnvFile is set but
          urlVar is null. urlVar is required when urlEnvFile is used.
        '';
      }
      {
        assertion =
          inst.urlVar == null
          || builtins.match "^[A-Za-z_][A-Za-z0-9_]*$" inst.urlVar != null;
        message = ''
          inspr.paimos-cli.instances."${name}".urlVar must be a valid shell environment
          identifier matching [A-Za-z_][A-Za-z0-9_]*.
        '';
      }
    ]) cfg.instances);

    warnings = deprecatedCredentialWarnings;

    home.activation.bootstrapPaimosConfig = lib.hm.dag.entryAfter (
      [ "writeBoundary" ]
      ++ lib.optional (config.inspr.secrets.agents.enable or false) "materializeAgentSecrets"
    ) ''
      set -e

      CONFIG_DIR="${config.home.homeDirectory}/.paimos"
      CONFIG_FILE="$CONFIG_DIR/config.yaml"

      umask 0077
      mkdir -p "$CONFIG_DIR"
      chmod 0700 "$CONFIG_DIR"

      # Rollout guard: never replace a legacy credential-bearing config. The
      # structural check emits only a boolean, captured below; stderr is hidden
      # so malformed YAML cannot echo configuration content into activation
      # logs. A parse failure is also fail-closed.
      if [[ -f "$CONFIG_FILE" ]]; then
        if ! legacy_api_key_present="$(${pkgs.yq-go}/bin/yq -r '[.. | select(tag == "!!map") | has("api_key")] | any' "$CONFIG_FILE" 2>/dev/null)"; then
          printf '%s\n' 'paimos-config: ERROR: existing config could not be validated without exposing it; refusing to replace it. Repair or migrate the config, then retry Home Manager.' >&2
          exit 1
        fi
        if [[ "$legacy_api_key_present" == "true" ]]; then
          printf '%s\n' 'paimos-config: ERROR: existing config uses legacy api_key; refusing to replace it. Before any new login, run paimos auth whoami once with all Paimos and legacy PPM auth overrides unset, then retry Home Manager. Follow the README migration order; only after this guard clears, use paimos auth login if authentication still fails.' >&2
          exit 1
        fi
      fi

      tmp="$(mktemp "$CONFIG_DIR/.config.yaml.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT
      chmod 0600 "$tmp"

      {
        printf '%s\n' ${lib.escapeShellArg "default_instance: ${yamlQuote cfg.defaultInstance}"}
        printf '%s\n' 'instances:'
        ${instanceFragments}
      } > "$tmp"

      mv -f "$tmp" "$CONFIG_FILE"

      echo "paimos-config: wrote routing without credentials to $CONFIG_FILE (${
        toString (lib.length (lib.attrNames cfg.instances))
      } instance(s) declared)"
    '';
  };
}
