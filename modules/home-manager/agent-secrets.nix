# ─────────────────────────────────────────────────────────────────────────
# inspr-modules/modules/home-manager/agent-secrets.nix
#
# Materialize agenix-encrypted env files into a per-user "agent-exception"
# directory at HM activation. Pairs with the env-file pattern (filename =
# variable name; contents = `KEY=value`) for `set -a; source $FILE; …`
# consumers.
#
# Architecture:
#
#   Encrypted side (consumer's repo, agenix-managed):
#     <encryptedRoot>/shared/<NAME>.age            → all hosts that opt in
#     <encryptedRoot>/host/<hostname>/<NAME>.age   → only that host
#
#   Decrypted side (per-host, activation-managed):
#     <decryptedDir>/<NAME>.env
#     mode 0400 (owner-read), dir mode 0500 (no manual writes)
#     READ-ONLY, ONE-WAY, activation-owned lifecycle:
#       rebuild = directory rebuilt against current declaration; orphans removed
#
# Daily interface:
#   ( set -a; source <decryptedDir>/<NAME>.env;
#     <command-that-uses-$NAME>; set +a )
#
# Implementation note: this is a Home Manager STANDALONE module. It does
# NOT use agenix's HM submodule because that submodule expects nix-darwin /
# NixOS context. Instead it uses the `age` CLI directly at activation time
# to decrypt the .age files. The user identity (`identityFile`) MUST be
# in the recipient list of every materialized secret.
#
# License: MIT (part of inspr-modules — see flake.nix).
# ─────────────────────────────────────────────────────────────────────────
{ config, pkgs, lib, hostname ? null, ... }:

let
  cfg = config.inspr.secrets.agents;

  # Helpers ----------------------------------------------------------------

  # Determine the hostname. Consumers that pass `hostname` via
  # extraSpecialArgs (the typical case in HM-on-NixOS / mkDarwinHome
  # patterns) get host-specific secret discovery for free. If neither
  # `hostname` is passed nor `cfg.hostname` is set, we throw at eval time
  # — silent zero-discovery is a worse failure mode than a clear error.
  hostnameValue =
    if cfg.hostname != null then cfg.hostname
    else if hostname != null then hostname
    else throw ''
      inspr.secrets.agents: hostname could not be determined.

      Provide it via either:
        (a) extraSpecialArgs in your homeConfigurations entry:
              extraSpecialArgs = { inherit inputs hostname; };
        (b) the option:
              inspr.secrets.agents.hostname = "your-host-name";

      Without a hostname, host-specific secrets at
      <encryptedRoot>/host/<hostname>/ are silently skipped — masking
      misconfigurations as "this host has no secrets."
    '';

  # Helper: list .age files in a directory (Nix-time, evaluated at flake
  # eval). Returns [] if the directory doesn't exist.
  ageFilesIn = dir:
    if builtins.pathExists dir
    then builtins.filter (n: lib.hasSuffix ".age" n)
                         (builtins.attrNames (builtins.readDir dir))
    else [];

  # Strip .age extension to get the variable name
  varNameOf = file: lib.removeSuffix ".age" file;

  # Discover the secrets at flake-eval time
  sharedDir = cfg.encryptedRoot + "/shared";
  hostDir   = cfg.encryptedRoot + "/host/${hostnameValue}";

  sharedFiles = ageFilesIn sharedDir;
  hostFiles   = ageFilesIn hostDir;

  # Pairs of (source-age-path, decrypted-target-name)
  allSecrets =
    (map (f: { src = "${sharedDir}/${f}"; name = varNameOf f; }) sharedFiles) ++
    (map (f: { src = "${hostDir}/${f}";   name = varNameOf f; }) hostFiles);

  # Newline-separated list of expected target basenames (for orphan cleanup)
  expectedBasenames = lib.concatStringsSep " " (map (s: "${s.name}.env") allSecrets);

in
{
  # Module options ---------------------------------------------------------
  # Namespace: `inspr.secrets.agents.*` — chosen for the atelier pattern (the
  # public library, i.e. this atelier, exports modules under this namespace;
  # sibling categories like `inspr.secrets.projects.*` and
  # `inspr.secrets.hosts.*` may follow as the architecture matures).
  options.inspr.secrets.agents = {
    enable = lib.mkEnableOption "materialize agent-exception secrets to <decryptedDir>";

    encryptedRoot = lib.mkOption {
      type        = lib.types.path;
      description = ''
        Source root for encrypted .age files. Must contain `shared/` and
        (optionally) `host/<hostname>/` subdirectories.

        REQUIRED: no sensible default for a public library — the path
        depends on the consumer flake's repo layout. A typical consumer
        sets this to a path-literal pointing at their nixcfg's
        `secrets/agents` directory.
      '';
      example = lib.literalExpression "../../secrets/agents";
    };

    decryptedDir = lib.mkOption {
      type        = lib.types.str;
      default     = "${config.home.homeDirectory}/.inspr/secrets/agents";
      defaultText = lib.literalExpression ''"''${config.home.homeDirectory}/.inspr/secrets/agents"'';
      description = ''
        Where decrypted .env files are materialized. Activation owns this
        dir entirely. Default derives from `config.home.homeDirectory` so
        the same module works for any user without further configuration.

        Path doctrine (INSPR-164, 2026-05-13): the canonical decrypted-side
        path is `~/.inspr/secrets/agents/<NAME>.env`. Hosts referencing this
        path can rely on it being identical fleet-wide, so cross-repo docs
        and helper scripts stay drift-free. Consumers may override for
        legacy compatibility, but new code should target the canonical
        default.

        Older inspr-modules versions (≤2026-05-12) defaulted to
        `~/Secrets/age/decrypted/agents/`. Consumers upgrading from that
        default should either accept the new path (and update references)
        or pin the legacy path explicitly via this option.
      '';
    };

    hostname = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      description = ''
        Hostname used to locate host-specific secrets at
        `<encryptedRoot>/host/<hostname>/`. When null, the module uses
        the `hostname` argument passed via extraSpecialArgs (typical for
        mkDarwinHome / nixos-rebuild patterns). If neither is set, the
        module throws at eval time rather than silently skipping host
        secrets.
      '';
    };

    identityFiles = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [
        "$HOME/.ssh/id_ed25519"
        "$HOME/.ssh/id_rsa"
      ];
      description = ''
        User SSH private keys `age` tries in order; the first one that
        exists at activation time is used for decryption. The selected
        key MUST correspond to a public key in the recipient list of
        every materialized secret. Variable expansion happens at
        activation time (shell), so `$HOME` is resolved per-user.

        Default tries modern ed25519 first, falls back to RSA — covers
        both fresh setups (which generate ed25519 by default) and older
        ones (which used RSA).
      '';
    };

    # Deprecated singular form. Prepended to `identityFiles` if set, so
    # consumers using the old API still work — but they should migrate
    # to the list form. Removal target: v0.2.0.
    identityFile = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      visible     = false;  # hidden from generated docs; keeps API surface clean
      description = ''
        DEPRECATED (since v0.1.1) — use `identityFiles` (list) instead.
        If set, this value is prepended to `identityFiles` for backward
        compatibility. Will be removed in v0.2.0.
      '';
    };
  };

  # Module config ----------------------------------------------------------
  config = lib.mkIf cfg.enable {
    # Deprecation warning: emit at eval time if the old singular option
    # is in use. (No assertion — we still honor it for backward compat.)
    warnings = lib.optional (cfg.identityFile != null) ''
      inspr.secrets.agents.identityFile is DEPRECATED — migrate to
      `inspr.secrets.agents.identityFiles = [ "<path1>" "<path2>" ]`.
      Will be removed in v0.2.0.
    '';

    # Activation script — runs after Home Manager's writeBoundary so the
    # `age` CLI (installed via home.packages from agenix) is on PATH.
    home.activation.materializeAgentSecrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -e

      DECRYPTED_DIR="${cfg.decryptedDir}"
      AGE_BIN="${pkgs.age}/bin/age"

      # Pick the first existing SSH identity from the configured list.
      # Backward-compat: if the deprecated singular `identityFile` was set,
      # it's prepended to the search order.
      IDENTITY=""
      ${lib.concatMapStringsSep "\n" (path: ''
        if [[ -z "$IDENTITY" && -f "${path}" ]]; then
          IDENTITY="${path}"
        fi
      '') (lib.optional (cfg.identityFile != null) cfg.identityFile ++ cfg.identityFiles)}

      if [[ -z "$IDENTITY" ]]; then
        echo "agent-secrets: ERROR — no SSH identity found among:" >&2
        ${lib.concatMapStringsSep "\n" (path: ''
          echo "  - ${path}" >&2
        '') (lib.optional (cfg.identityFile != null) cfg.identityFile ++ cfg.identityFiles)}
        echo "  Generate one with: ssh-keygen -t ed25519" >&2
        exit 1
      fi
      echo "agent-secrets: using identity $IDENTITY"

      mkdir -p "$DECRYPTED_DIR"
      # Open the dir for writes during this activation. Lock it back to
      # 0500 (no manual writes possible) at the end of the script.
      chmod 0700 "$DECRYPTED_DIR"

      # CRITICAL invariant: the decrypted dir is mode 0500 OUTSIDE
      # activation, always. The chmod at the end of this script does
      # that on success. The trap guarantees it on ANY failure path
      # too — without this, a mid-loop decrypt failure (corrupt .age,
      # missing recipient, age binary error) would leave the dir at
      # 0700 until the next successful activation, allowing manual
      # writes in the meantime. (Audit-flagged: INSPR-55.)
      trap 'chmod 0500 "$DECRYPTED_DIR" 2>/dev/null || true' EXIT

      # Build the expected file set (computed at Nix eval time; baked into script)
      expected="${expectedBasenames}"

      # Decrypt every declared secret
      ${lib.concatMapStringsSep "\n" (s: ''
        echo "agent-secrets: decrypting ${s.name}"
        target="$DECRYPTED_DIR/${s.name}.env"
        # Remove prior file first — previous activation set mode 0400, so
        # the `>` truncate-open below would fail with Permission denied.
        # rm honors the read-only file mode (dir is 0700 during activation).
        rm -f "$target"
        # umask narrows default file perms so the plaintext is never even
        # momentarily readable by other accounts.
        umask 0277
        "$AGE_BIN" --decrypt --identity "$IDENTITY" "${s.src}" > "$target"
        chmod 0400 "$target"
      '') allSecrets}

      # Cleanup orphans: remove .env files not in current declaration
      for f in "$DECRYPTED_DIR"/*.env; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        case " $expected " in
          *" $base "*) ;;  # expected, keep
          *)
            echo "agent-secrets: removing orphan $base"
            # chflags is macOS-only (BSD nouchg flag clearing). The `|| true`
            # makes this a silent no-op on Linux, which is correct (Linux
            # doesn't use the immutable flag in this pipeline).
            chflags nouchg "$f" 2>/dev/null || true
            rm -f "$f"
            ;;
        esac
      done

      # Lock the directory: no further writes possible without explicit chmod.
      # This is the "one-way street" guarantee from the architecture.
      chmod 0500 "$DECRYPTED_DIR"
    '';
  };
}
