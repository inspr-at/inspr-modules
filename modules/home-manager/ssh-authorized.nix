# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              INSPR — Declarative SSH authorized_keys (HM module)             ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Manage `~/.ssh/authorized_keys` declaratively from a named-key map plus a
# trust list. Replaces the manual `ssh-copy-id` drift pattern with a
# build-time source of truth.
#
# Usage (consumer's home.nix):
#
#   inspr.ssh.authorized = {
#     enable = true;
#     keys = {
#       "markus@m5"    = "ssh-ed25519 AAAAC3...m5";
#       "markus@imac0" = "ssh-ed25519 AAAAC3...imac0";
#       "deploy@gpc0"  = "ssh-ed25519 AAAAC3...gpc0";
#     };
#     trust = [ "markus@m5" "markus@imac0" ];   # admit these; deploy@gpc0 stays out
#   };
#
# Co-existence guarantee
# ──────────────────────
# This module owns ONLY a marker-delimited block in authorized_keys. Lines
# OUTSIDE the markers are preserved unchanged across activations. So you
# can keep manual entries (Headscale deploy keys, GitHub Actions OIDC,
# one-off recovery keys) above or below the managed block without losing
# them when the module rebuilds. The default markers are:
#
#   # >>> inspr.ssh.authorized BEGIN — declaratively managed, do not edit between markers
#   # alias: <alias-1>
#   <ssh-key-1>
#   # alias: <alias-2>
#   <ssh-key-2>
#   # <<< inspr.ssh.authorized END
#
# OpenSSH StrictModes
# ───────────────────
# `~/.ssh` and `~/.ssh/authorized_keys` are permission-sensitive — sshd
# refuses to read `authorized_keys` if either is group/world-writable, or
# if the file is a symlink into /nix/store (world-readable). So we use an
# HM activation script that writes the file directly with mode 0600 and
# ensures `~/.ssh` is mode 0700, NOT `home.file` (which would symlink).
#
# Determinism
# ───────────
# Trust list is sorted at eval time before rendering. Two consumers with
# the same `keys` and the same `trust` set always produce byte-identical
# managed blocks regardless of input order — useful for diff review and
# git noise minimization.
#
# What this module does NOT do (filed as follow-ups)
# ──────────────────────────────────────────────────
#   - INSPR-73: NixOS-side variant rendering into
#     `users.users.<u>.openssh.authorizedKeys.keys` (this one is HM-only)
#   - INSPR-74: file-per-key keyring layout for fleet-scale (~10+ keys)
#   - INSPR-75: eval-time `ssh-keygen -l` validation of each key
#
# License: MIT (part of inspr-modules — see flake.nix).
# ─────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.inspr.ssh.authorized;

  # Look up a key by alias; throw with full context on miss. Silent
  # fall-through (e.g. emitting a key labeled "ghost" with no body) would
  # be a real footgun — empty-body lines in authorized_keys are silently
  # ignored by sshd, so the host would just stop trusting that alias
  # without any warning. Throw makes the misconfiguration visible at
  # `nix flake check` time.
  keyByAlias =
    alias:
    cfg.keys.${alias} or (throw ''
      inspr.ssh.authorized: alias "${alias}" listed in `trust` but not declared in `keys`.
      Declared aliases: ${toString (lib.attrNames cfg.keys)}
    '');

  # Sort the trust list at eval time. Determinism property: two consumers
  # with equivalent inputs always produce a byte-identical managed block,
  # so re-ordering the source `trust = [ ... ]` list doesn't dirty the
  # activation diff or cause spurious git noise on rebuilds.
  sortedTrust = lib.sort (a: b: a < b) cfg.trust;

  # Render the managed block. Each admitted alias contributes two lines:
  # a `# alias: <name>` comment for human-readable audit trail, then the
  # key body itself. Whole block is enclosed in begin/end markers so the
  # activation script can replace it in-place without disturbing the rest
  # of the file.
  managedBlock = lib.concatStringsSep "\n" (
    [ cfg.markerBegin ]
    ++ lib.flatten (
      map (alias: [
        "# alias: ${alias}"
        (keyByAlias alias)
      ]) sortedTrust
    )
    ++ [ cfg.markerEnd ]
  );

  # The managed block as a Nix-store file. Written once at eval time;
  # the activation script reads from this path so the block is reproducible
  # and content-addressed (changes to the trust set produce a new derivation
  # hash, naturally invalidating the previous activation).
  managedBlockFile = pkgs.writeText "inspr-ssh-authorized-block" managedBlock;
in
{
  options.inspr.ssh.authorized = {
    enable = lib.mkEnableOption "declarative SSH authorized_keys management via aliased key map";

    keys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Named SSH public keys: alias → full key string (the entire
        `ssh-<type> <material> <comment>` line as it would appear in
        `authorized_keys`).

        Aliases are arbitrary identifiers — common conventions are
        `<user>@<host>` (e.g. `"markus@m5"`) or `<purpose>` (e.g.
        `"deploy-bot"`). They show up as `# alias: <name>` comments in
        the rendered authorized_keys for audit traceability.

        Declaring a key here does NOT admit it — see `trust`.
      '';
      example = lib.literalExpression ''
        {
          "markus@m5"    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... markus@m5";
          "markus@imac0" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... markus@imac0";
          "deploy@gpc0"  = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... deploy@gpc0";
        }
      '';
    };

    trust = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of aliases (keys in `keys`) admitted to this user's
        `~/.ssh/authorized_keys`. An alias listed here that isn't
        declared in `keys` throws an evaluation error — silent
        fall-through would be a footgun (empty-body lines are silently
        ignored by sshd, so the host would just stop trusting that
        alias without any visible failure).

        Order does not matter — the trust list is sorted before
        rendering so equivalent inputs produce byte-identical output.
      '';
      example = lib.literalExpression ''[ "markus@m5" "markus@imac0" ]'';
    };

    markerBegin = lib.mkOption {
      type = lib.types.str;
      default = "# >>> inspr.ssh.authorized BEGIN — declaratively managed, do not edit between markers";
      description = ''
        First line of the managed block. The activation script uses this
        verbatim as the search anchor for in-place replacement, so
        changing it after first activation would orphan the previous
        block (it would be appended-not-replaced). Stable default;
        override only if the marker syntax conflicts with another
        consumer of authorized_keys.
      '';
    };

    markerEnd = lib.mkOption {
      type = lib.types.str;
      default = "# <<< inspr.ssh.authorized END";
      description = "Last line of the managed block. Same orphaning caveat as `markerBegin`.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Eval-time sanity: warn (don't fail) if `enable = true` but `trust`
    # is empty. Most likely a half-finished config — either the user
    # forgot to populate `trust` or they intentionally want an empty
    # managed block (rare but valid: explicitly revoke all previously-
    # trusted keys via the empty-block render).
    warnings = lib.optional (cfg.enable && cfg.trust == [ ]) ''
      inspr.ssh.authorized: enabled but `trust` is empty. The managed block
      will render as just the begin/end markers — no keys admitted. If this
      is intentional (revocation), ignore this warning. Otherwise populate
      `trust` with aliases from `keys`.
    '';

    home.activation.insprSshAuthorized = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -e

      AUTH_FILE="$HOME/.ssh/authorized_keys"
      SSH_DIR="$HOME/.ssh"
      BLOCK_SRC="${managedBlockFile}"
      MARKER_BEGIN=${lib.escapeShellArg cfg.markerBegin}
      MARKER_END=${lib.escapeShellArg cfg.markerEnd}

      # Ensure ~/.ssh exists with sshd-acceptable permissions. sshd refuses
      # to read authorized_keys if ~/.ssh is group/world-writable.
      mkdir -p "$SSH_DIR"
      chmod 0700 "$SSH_DIR"

      # Compute the new file content. Three cases:
      #   1. file doesn't exist → just write the managed block as the whole file
      #   2. file exists, has markers → replace the marker-delimited section
      #   3. file exists, no markers → append the managed block to the end
      # In every case, end up with mode 0600.

      tmp="$(${pkgs.coreutils}/bin/mktemp "$SSH_DIR/.authorized_keys.XXXXXX")"
      # Hardening: tmp file gets the strict mode IMMEDIATELY so any plaintext
      # we write to it is never even momentarily world-readable.
      chmod 0600 "$tmp"
      trap 'rm -f "$tmp"' EXIT

      if [ ! -f "$AUTH_FILE" ]; then
        # Case 1: clean slate
        ${pkgs.coreutils}/bin/cat "$BLOCK_SRC" > "$tmp"
        echo "" >> "$tmp"
      elif ${pkgs.gnugrep}/bin/grep -qF "$MARKER_BEGIN" "$AUTH_FILE"; then
        # Case 2: in-place replacement. awk is the right tool — single pass,
        # streams the file, prints everything outside the marker block plus
        # our new managed block in place of the old one.
        ${pkgs.gawk}/bin/awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" -v blockfile="$BLOCK_SRC" '
          BEGIN { in_block = 0; printed_block = 0 }
          $0 == begin {
            in_block = 1
            # Splice in the new block (stream the file in)
            while ((getline line < blockfile) > 0) print line
            close(blockfile)
            printed_block = 1
            next
          }
          $0 == end {
            in_block = 0
            next
          }
          in_block { next }
          { print }
          END {
            # Defensive: if begin marker was present but end marker was
            # missing (truncated file?), the in_block flag would still be
            # set here. We've already printed the new block, so the rest
            # of the file is gone — that's the right outcome (the file
            # was already corrupt; we cleanly replaced it).
            if (printed_block == 0) {
              # Should not be reachable given the outer if-grep above, but
              # be paranoid: append the new block if for any reason the
              # match failed inside awk.
              while ((getline line < blockfile) > 0) print line
              close(blockfile)
            }
          }
        ' "$AUTH_FILE" > "$tmp"
      else
        # Case 3: existing file, no marker — append (preserve current content)
        ${pkgs.coreutils}/bin/cat "$AUTH_FILE" > "$tmp"
        # Ensure trailing newline before our block so the BEGIN marker lands
        # on its own line even if the original file lacked a final newline.
        ${pkgs.coreutils}/bin/printf '\n' >> "$tmp"
        ${pkgs.coreutils}/bin/cat "$BLOCK_SRC" >> "$tmp"
        echo "" >> "$tmp"
      fi

      # Atomic move into place. mv preserves the 0600 mode set on $tmp above.
      ${pkgs.coreutils}/bin/mv -f "$tmp" "$AUTH_FILE"
      # Defensive re-chmod in case the file existed previously with looser perms.
      chmod 0600 "$AUTH_FILE"

      echo "inspr.ssh.authorized: $AUTH_FILE updated (${toString (lib.length sortedTrust)} keys admitted)"
    '';
  };
}
