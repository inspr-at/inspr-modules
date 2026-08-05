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
# SPDX-License-Identifier: AGPL-3.0-only
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

  # All discovered variable names — used by the `requireFiles` validation.
  discoveredNames = map varNameOf (sharedFiles ++ hostFiles);

  # Eval-time validation (INSPR-263): secret basenames land inside the
  # activation script and become filenames under decryptedDir, so restrict
  # them to a conservative alphabet before any rendering. Env-identifier
  # chars plus `-` and `.` — dashes are in real use for materialized SSH
  # key names (e.g. `m5-personal-userkey.env`); everything shell-dangerous
  # (spaces, quotes, `$`, backticks, backslashes, newlines) is rejected.
  invalidNames =
    builtins.filter (n: builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]*" n == null) discoveredNames;

  _validateNames =
    if invalidNames == [ ] then null
    else throw ''

      inspr.secrets.agents: secret file name(s) outside the allowed
      alphabet ([A-Za-z0-9_][A-Za-z0-9_.-]*):
      ${lib.concatMapStringsSep "\n      " (n: "  - ${n}.age") invalidNames}

      Rename the .age file(s) — names become shell-visible filenames and
      env-file identifiers; spaces, quotes, and other shell metacharacters
      are not supported.
    '';

  # Eval-time validation: every name in `requireFiles` MUST be discoverable
  # via `readDir` of the flake source. Catches the common failure mode where
  # a new `.age` file exists on disk but is UNTRACKED in git, so the flake
  # source closure doesn't include it → discovery silently misses → secret
  # is never materialized → consumer wonders why their env-file is empty.
  missingRequired = lib.subtractLists discoveredNames cfg.requireFiles;

  _validateRequired =
    if missingRequired == [] then null
    else throw ''

      inspr.secrets.agents: required secret file(s) missing from flake source:
      ${lib.concatMapStringsSep "\n      " (n: "  - ${n}.age") missingRequired}

      Each must exist at one of:
        ${toString sharedDir}/<NAME>.age
        ${toString hostDir}/<NAME>.age

      Most common cause: the .age file is on disk but UNTRACKED in git.
      Nix flake source builds only see git-tracked files, so `readDir` of the
      flake-evaluated path doesn't see it. Stage with:

          git add <encryptedRoot>/{shared,host/<host>}/<NAME>.age

      and re-run `home-manager switch`. Commit is NOT required — staging
      alone is enough for the flake to include the file in source.
    '';

  # Newline-separated list of expected target basenames (for orphan cleanup):
  # one per line so the matcher is exact (`grep -Fxq`) — a space-delimited
  # list let a basename containing a space corrupt the match (INSPR-263).
  # Forces `_validateRequired` + `_validateNames` so any throw fires before
  # the activation script renders.
  expectedBasenames =
    builtins.seq _validateRequired (
      builtins.seq _validateNames (
        lib.concatMapStringsSep "\n" (s: "${s.name}.env") allSecrets
      )
    );

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

    requireFiles = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ ];
      example     = [ "PPMAPIKEY" "HOMEWIFI" ];
      description = ''
        Optional list of secret basenames (without `.age`/`.env`) that MUST
        be discoverable at HM-eval time in either `<encryptedRoot>/shared/`
        or `<encryptedRoot>/host/<hostname>/`. If any are missing, evaluation
        throws with a diagnostic pointing at the most common cause: an
        untracked `.age` file invisible to the flake source closure.

        Without this option, a typo in `secrets.nix` or an untracked `.age`
        causes silent skip — the consumer rebuilds successfully but the
        env-file never materializes. Use this to fail loud instead.

        Recommended wiring: derive the list from your `secrets.nix` so the
        recipient declarations are the single source of truth. Example:

            let
              secrets = import ./secrets/secrets.nix;
              keys    = builtins.attrNames secrets;
              isFor   = k:
                lib.hasPrefix "agents/shared/" k
                || lib.hasPrefix "agents/host/''${hostname}/" k;
              nameOf  = k:
                lib.removeSuffix ".age"
                  (lib.last (lib.splitString "/" k));
            in
              inspr.secrets.agents.requireFiles =
                map nameOf (builtins.filter isFor keys);
      '';
    };

    retiredDirs = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ "${config.home.homeDirectory}/Secrets/age/decrypted/agents" ];
      defaultText = lib.literalExpression ''[ "''${config.home.homeDirectory}/Secrets/age/decrypted/agents" ]'';
      description = ''
        Former decryptedDir locations to check for plaintext residue at
        activation (INSPR-262). Any listed directory that differs from the
        current `decryptedDir` and still contains `*.env` files triggers a
        loud warning — never deletion: the files are secrets, and disposal
        is the operator's explicit call.

        The default is the module's own pre-2026-05-13 default
        (`~/Secrets/age/decrypted/agents/`, retired by the INSPR-164 path
        flip): hosts that upgraded through that flip may still hold
        plaintext there, untracked and never rotated. Add entries when you
        retire a custom decryptedDir; set `[ ]` to silence the check.
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

      DECRYPTED_DIR=${lib.escapeShellArg cfg.decryptedDir}
      AGE_BIN="${pkgs.age}/bin/age"

      # Residue check (INSPR-262): warn when a retired decryptedDir still
      # holds plaintext .env files — nothing tracks or rotates them there.
      # Warn ONLY, never delete: the files are secrets, disposal is the
      # operator's explicit call. Runs before the identity requirement so
      # the warning fires even when the rest of activation fails.
      ${lib.concatMapStringsSep "\n" (dir: ''
        RETIRED=${lib.escapeShellArg dir}
        if [[ "$RETIRED" != "$DECRYPTED_DIR" && -d "$RETIRED" ]]; then
          residue_count="$(${pkgs.findutils}/bin/find "$RETIRED" -maxdepth 1 -name '*.env' -type f 2>/dev/null | ${pkgs.coreutils}/bin/wc -l | ${pkgs.coreutils}/bin/tr -d ' ')"
          if [[ "$residue_count" -gt 0 ]]; then
            echo "agent-secrets: WARNING — $residue_count plaintext .env file(s) remain in retired secrets dir: $RETIRED" >&2
            echo "agent-secrets:           that path is no longer managed: nothing tracks, rotates, or cleans those files." >&2
            echo "agent-secrets:           after confirming replacements exist under $DECRYPTED_DIR, inspect and remove the residue." >&2
          fi
        fi
      '') cfg.retiredDirs}

      # Pick the first existing SSH identity from the configured list.
      # Backward-compat: if the deprecated singular `identityFile` was set,
      # it's prepended to the search order.
      # DELIBERATE EXCEPTION (INSPR-263): identity paths are interpolated
      # unescaped because `$HOME`-relative entries are documented to expand
      # at activation time. Everything else in this script is escaped.
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

      # Expected file set: one basename per line (computed at Nix eval time;
      # baked into the script as a single escaped literal).
      expected=${lib.escapeShellArg expectedBasenames}

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
        "$AGE_BIN" --decrypt --identity "$IDENTITY" ${lib.escapeShellArg s.src} > "$target"
        chmod 0400 "$target"
      '') allSecrets}

      # Cleanup orphans: remove .env files not in current declaration.
      # Exact whole-line match against the newline list — immune to spaces
      # or glob characters in stray basenames (INSPR-263).
      for f in "$DECRYPTED_DIR"/*.env; do
        [ -e "$f" ] || continue
        base="$(basename "$f")"
        if printf '%s\n' "$expected" | ${pkgs.gnugrep}/bin/grep -Fxq -- "$base"; then
          : # expected, keep
        else
          echo "agent-secrets: removing orphan $base"
          # chflags is macOS-only (BSD nouchg flag clearing). The `|| true`
          # makes this a silent no-op on Linux, which is correct (Linux
          # doesn't use the immutable flag in this pipeline).
          chflags nouchg "$f" 2>/dev/null || true
          rm -f "$f"
        fi
      done

      # Lock the directory: no further writes possible without explicit chmod.
      # This is the "one-way street" guarantee from the architecture.
      chmod 0500 "$DECRYPTED_DIR"
    '';
  };
}
