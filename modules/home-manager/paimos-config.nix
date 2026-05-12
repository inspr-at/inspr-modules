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
#     # URL as Nix-time literal (public hosts, hard-coded URLs):
#     instances.mine = {
#       url           = "https://your-paimos.example.com";
#       apiKeyEnvFile = "/run/agenix/your-paimos-api-key";  # or ~/.../X.env
#       apiKeyVar     = "PAIMOS_API_KEY";
#     };
#     # URL as env-file lookup (private hosts, agenix-encrypted URLs):
#     instances.work = {
#       urlEnvFile    = "${config.home.homeDirectory}/Secrets/X/WORKURL.env";
#       urlVar        = "WORKURL";
#       apiKeyEnvFile = "${config.home.homeDirectory}/Secrets/X/WORKAPIKEY.env";
#       apiKeyVar     = "WORKAPIKEY";
#     };
#   };
#
# Per instance, exactly ONE of {url, urlEnvFile} must be set. urlEnvFile
# requires urlVar. Both validated at eval time via assertions.
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
  #   - api_key + url are written as SINGLE-QUOTED YAML scalars — that's a
  #     literal string in YAML, which makes any character safe except
  #     a single quote (escaped per spec by doubling: ' → '').
  #   - Without this, leading `*`/`&`/`[`/`{` would be interpreted as
  #     anchors/aliases/inline structures; embedded `:` would split
  #     the key/value parse; embedded `#` would start a comment.
  #
  # Two URL paths (INSPR-174):
  #   - inst.url != null      → literal: emitted verbatim into the script
  #   - inst.urlEnvFile != null → sourced from env file at activation, then
  #                                YAML-escaped same as api_key
  #
  # The eval-time assertions guarantee exactly one of these is non-null.
  mkInstanceFragment = name: inst:
    let
      urlFromLiteral = inst.url != null;
      urlFromEnv     = inst.urlEnvFile != null;
    in ''
    if [[ -f "${inst.apiKeyEnvFile}" ]] ${
      lib.optionalString urlFromEnv
        ''&& [[ -f "${inst.urlEnvFile}" ]]''
    }; then
      (
        set -a
        # shellcheck disable=SC1090
        source "${inst.apiKeyEnvFile}"
        ${lib.optionalString urlFromEnv ''
        # shellcheck disable=SC1090
        source "${inst.urlEnvFile}"
        ''}
        set +a
        # ── URL resolution ────────────────────────────────────────────
        ${if urlFromLiteral then ''
        url_value=${lib.escapeShellArg inst.url}
        '' else ''
        if url_value="$(printenv ${lib.escapeShellArg inst.urlVar})"; then
          if [[ -z "$url_value" ]]; then
            echo "paimos-config: WARN ${name}: ${inst.urlVar} is set but empty in ${inst.urlEnvFile}; skipping" >&2
            exit 0
          fi
        else
          echo "paimos-config: WARN ${name}: ${inst.urlVar} not set after sourcing ${inst.urlEnvFile} (typo? wrong env file?); skipping" >&2
          exit 0
        fi
        ''}
        # ── API key resolution ────────────────────────────────────────
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
            url_escaped=$(printf '%s' "$url_value" | ${pkgs.gawk}/bin/awk '{ gsub(/\x27/, "\x27\x27"); print }')
            key_escaped=$(printf '%s' "$key_value" | ${pkgs.gawk}/bin/awk '{ gsub(/\x27/, "\x27\x27"); print }')
            echo "    ${name}:"
            echo "        url: '$url_escaped'"
            echo "        api_key: '$key_escaped'"
          else
            echo "paimos-config: WARN ${name}: ${inst.apiKeyVar} is set but empty in ${inst.apiKeyEnvFile}; skipping" >&2
          fi
        else
          echo "paimos-config: WARN ${name}: ${inst.apiKeyVar} not set after sourcing ${inst.apiKeyEnvFile} (typo? wrong env file?); skipping" >&2
        fi
      )
    else
      ${if urlFromEnv then ''
      [[ -f "${inst.apiKeyEnvFile}" ]] || echo "paimos-config: WARN ${name}: ${inst.apiKeyEnvFile} not found; skipping" >&2
      [[ -f "${inst.urlEnvFile}"    ]] || echo "paimos-config: WARN ${name}: ${inst.urlEnvFile} not found; skipping" >&2
      '' else ''
      echo "paimos-config: WARN ${name}: ${inst.apiKeyEnvFile} not found; skipping" >&2
      ''}
    fi
  '';

  # Only render fragments for well-formed instances. Broken ones (e.g. both
  # url and urlEnvFile set, or neither) still fire the eval-time assertions
  # — but `assertions` doesn't short-circuit the rest of `config` evaluation,
  # so we must independently guard the renderer to avoid `cannot coerce null
  # to a string` errors before the assertion check surfaces the real cause.
  wellFormedInstances = lib.filterAttrs (_: inst:
    # Exactly one of {url, urlEnvFile} set (XOR)
    ((inst.url != null) != (inst.urlEnvFile != null))
    # urlVar required when urlEnvFile is set
    && (inst.urlEnvFile == null || inst.urlVar != null)
  ) cfg.instances;

  instanceFragments = lib.concatStringsSep "\n" (
    lib.mapAttrsToList mkInstanceFragment wellFormedInstances
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
          - url           Nix-time literal HTTPS endpoint, OR
            urlEnvFile + urlVar — absolute path to a KEY=value env file +
                          variable name holding the URL (for agenix-encrypted
                          URLs that shouldn't be Nix-time literals)
          - apiKeyEnvFile absolute path to a KEY=value env file (typically
                          materialized by inspr.secrets.agents)
          - apiKeyVar     variable name inside the env file holding the API key
        Activation sources each env file in a subshell, extracts the variable,
        and writes config.yaml atomically. Missing files → skipped with a WARN.
        Exactly ONE of `{url, urlEnvFile}` must be set per instance (asserted).
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Instance URL as a Nix-time string literal (e.g.
                "https://your-paimos.example.com"). Use this for public
                or hard-coded URLs. Mutually exclusive with urlEnvFile;
                exactly one must be set.
              '';
            };
            urlEnvFile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Absolute path to a KEY=value env file holding the
                instance URL (typically materialized by
                inspr.secrets.agents). Use this for agenix-encrypted
                URLs that shouldn't appear as Nix-time literals.
                Requires `urlVar` to identify the variable inside.
                Mutually exclusive with `url`.
              '';
              example = "/run/agenix/your-paimos-url";
            };
            urlVar = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = ''
                Variable name inside `urlEnvFile` holding the instance
                URL. Required when `urlEnvFile` is set; ignored otherwise.
              '';
              example = "WORKURL";
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
    # (Audit-flagged: INSPR-54 + INSPR-69; INSPR-174 added the URL invariants.)
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
    ]
    # INSPR-174: per-instance URL invariants. Exactly one of {url, urlEnvFile}
    # must be set; urlEnvFile additionally requires urlVar. Each instance
    # contributes its own pair of assertions for precise error attribution.
    ++ lib.concatLists (lib.mapAttrsToList (name: inst: [
      {
        assertion =
          (inst.url != null && inst.urlEnvFile == null)
          || (inst.url == null && inst.urlEnvFile != null);
        message = ''
          inspr.paimos-cli.instances."${name}": exactly ONE of
          {url, urlEnvFile} must be set (got url=${
            if inst.url == null then "null" else "\"${inst.url}\""
          }, urlEnvFile=${
            if inst.urlEnvFile == null then "null" else "\"${inst.urlEnvFile}\""
          }).
        '';
      }
      {
        assertion = (inst.urlEnvFile == null) || (inst.urlVar != null);
        message = ''
          inspr.paimos-cli.instances."${name}": urlEnvFile is set but
          urlVar is null. urlVar is required when urlEnvFile is used —
          it tells the activation script which variable inside the env
          file holds the URL.
        '';
      }
    ]) cfg.instances);

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
