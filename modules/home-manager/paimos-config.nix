# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              INSPR — Auto-bootstrap paimos-cli config                        ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Materialize ~/.paimos/config.yaml from agent-secrets env files at HM
# activation time, so a fresh INSPR-onboarded host gets `paimos` CLI ready
# to use without the manual `paimos auth login --url ... --api-key ...` step.
#
# Pairs with:
#   - inspr.secrets.agents (provides the materialized .env files)
#   - paimos-cli in home.packages (the binary that reads this config)
#
# Architecture:
#   - Each named instance declares: URL + path to KEY=value env file + var name
#   - Activation sources each env file in a subshell (scoped exposure),
#     extracts the variable, writes ~/.paimos/config.yaml atomically
#   - File mode 0600, dir mode 0700 — never world-readable
#   - Idempotent: re-runs each activation; declarative wins over manual edits
#   - Safe-degrade: missing env file → instance skipped with a stderr WARN
#     (so enabling this module without agent-secrets configured doesn't
#      break activation; the YAML just won't include that instance)
#
# Usage (consumer's home.nix):
#   imports = [ inputs.inspr-modules.homeManagerModules.paimos-config ];
#   inspr.paimos-cli = {
#     enable = true;
#     defaultInstance = "mine";
#     instances.mine = {
#       url           = "https://your-paimos.example.com";
#       apiKeyEnvFile = "/run/agenix/your-paimos-api-key";  # or ~/.../X.env
#       apiKeyVar     = "PAIMOS_API_KEY";
#     };
#   };
#
# Note: `instances` defaults to `{}` — consumers MUST declare at least one
# instance. There is no sensible cross-context default for a public library.
#
# License: MIT (part of inspr-modules — see flake.nix).
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.inspr.paimos-cli;

  # Build one YAML fragment per declared instance. Wraps each in a subshell
  # so the sourced env vars don't bleed into the next iteration.
  #
  # YAML safety (audit-flagged: INSPR-52):
  #   - api_key is written as a SINGLE-QUOTED YAML scalar — that's a
  #     literal string in YAML, which makes any character safe except
  #     a single quote (escaped per spec by doubling: ' → '').
  #   - Without this, leading `*`/`&`/`[`/`{` would be interpreted as
  #     anchors/aliases/inline structures; embedded `:` would split
  #     the key/value parse; embedded `#` would start a comment.
  mkInstanceFragment = name: inst: ''
    if [[ -f "${inst.apiKeyEnvFile}" ]]; then
      (
        set -a
        # shellcheck disable=SC1090
        source "${inst.apiKeyEnvFile}"
        set +a
        # printenv exits 1 (no output) if the var is unset; exits 0 with
        # empty output if the var is set-but-empty. Distinguish — typo
        # catches are valuable. (Audit-flagged: INSPR-62.)
        if key_value="$(printenv ${lib.escapeShellArg inst.apiKeyVar})"; then
          if [[ -n "$key_value" ]]; then
            # YAML single-quote escape via awk: each 0x27 (single quote)
            # is doubled per YAML spec (literal single-quoted scalars use
            # 0x27 0x27 to represent a single 0x27). Hex escapes throughout
            # (no literal quote characters) keep this comment + script
            # safe inside Nix multi-line strings.
            # Explicit nix-store path so we don\x27t depend on PATH at
            # activation time (HM activation has a sparse PATH).
            escaped=$(printf '%s' "$key_value" | ${pkgs.gawk}/bin/awk '{ gsub(/\x27/, "\x27\x27"); print }')
            echo "    ${name}:"
            echo "        url: ${inst.url}"
            echo "        api_key: '$escaped'"
          else
            echo "paimos-config: WARN ${name}: ${inst.apiKeyVar} is set but empty in ${inst.apiKeyEnvFile}; skipping" >&2
          fi
        else
          echo "paimos-config: WARN ${name}: ${inst.apiKeyVar} not set after sourcing ${inst.apiKeyEnvFile} (typo? wrong env file?); skipping" >&2
        fi
      )
    else
      echo "paimos-config: WARN ${name}: ${inst.apiKeyEnvFile} not found; skipping" >&2
    fi
  '';

  instanceFragments = lib.concatStringsSep "\n" (
    lib.mapAttrsToList mkInstanceFragment cfg.instances
  );

  # No default instances. Consumers MUST declare their own — there's no
  # cross-context-sensible default URL or secret-path for a public library.
  defaultInstances = { };
in
{
  options.inspr.paimos-cli = {
    enable = lib.mkEnableOption "auto-bootstrap ~/.paimos/config.yaml from agent-secrets env files";

    defaultInstance = lib.mkOption {
      type = lib.types.str;
      description = ''
        Which configured instance becomes the default for `paimos` CLI
        invocations that don't pass `--instance`. Must be a key in `instances`.
      '';
      example = "mine";
    };

    instances = lib.mkOption {
      description = ''
        Named PAIMOS instances to materialize into ~/.paimos/config.yaml.
        Each instance provides:
          - url           the instance's HTTPS endpoint
          - apiKeyEnvFile absolute path to a KEY=value env file (typically
                          materialized by inspr.secrets.agents)
          - apiKeyVar     variable name inside the env file holding the API key
        Activation sources each env file in a subshell, extracts the variable,
        and writes config.yaml atomically. Missing files → skipped with a WARN.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              description = "Instance URL (e.g. https://your-paimos.example.com)";
            };
            apiKeyEnvFile = lib.mkOption {
              type = lib.types.str;
              description = "Absolute path to env file containing the API key";
            };
            apiKeyVar = lib.mkOption {
              type = lib.types.str;
              description = "Variable name inside the env file holding the API key";
            };
          };
        }
      );
      default = defaultInstances;
      defaultText = lib.literalExpression "{ }";
      example = lib.literalExpression ''
        {
          mine = {
            url           = "https://your-paimos.example.com";
            apiKeyEnvFile = "/run/agenix/your-paimos-api-key";
            apiKeyVar     = "PAIMOS_API_KEY";
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Eval-time invariants — fail loudly at switch time, not at paimos
    # runtime with cryptic "instance not configured" errors.
    # (Audit-flagged: INSPR-54 + INSPR-69.)
    assertions = [
      {
        assertion = (lib.attrNames cfg.instances) != [ ];
        message = ''
          inspr.paimos-cli.enable = true requires at least one entry in
          inspr.paimos-cli.instances. See `inspr.paimos-cli.instances`
          example for the expected shape.
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
    ];

    home.activation.bootstrapPaimosConfig = lib.hm.dag.entryAfter (
      [ "writeBoundary" ]
      # If agent-secrets is also enabled, sequence after it so the env files
      # are guaranteed to exist when our script reads them. The `or false`
      # keeps this module independently consumable — without it, importing
      # paimos-config without agent-secrets would fail eval with
      # "attribute 'secrets' missing." (Found by INSPR-72 module-eval suite.)
      ++ lib.optional (config.inspr.secrets.agents.enable or false) "materializeAgentSecrets"
    ) ''
      set -e

      CONFIG_DIR="${config.home.homeDirectory}/.paimos"
      CONFIG_FILE="$CONFIG_DIR/config.yaml"

      umask 0077
      mkdir -p "$CONFIG_DIR"
      chmod 0700 "$CONFIG_DIR"

      # Build YAML in a tmpfile then mv atomically (so a partial write
      # never leaves the consumer reading a half-written file).
      tmp="$(mktemp "$CONFIG_DIR/.config.yaml.XXXXXX")"
      # Cleanup on ANY exit path (success: mv removed it already; failure:
      # this trap removes the orphan to avoid dotfile garbage accumulation).
      # (Audit-flagged: INSPR-53.)
      trap 'rm -f "$tmp"' EXIT
      chmod 0600 "$tmp"

      {
        echo "default_instance: ${cfg.defaultInstance}"
        echo "instances:"
        ${instanceFragments}
      } > "$tmp"

      mv -f "$tmp" "$CONFIG_FILE"

      echo "paimos-config: wrote $CONFIG_FILE (${
        toString (lib.length (lib.attrNames cfg.instances))
      } instance(s) declared)"
    '';
  };
}
