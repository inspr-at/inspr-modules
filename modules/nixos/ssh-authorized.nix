# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║           INSPR — Declarative SSH authorized_keys (NixOS module)            ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# System-side counterpart to `inspr.ssh.authorized` (HM). Manages
# `users.users.<name>.openssh.authorizedKeys.keys` declaratively from a
# shared keyring + per-user trust list, with the same rich-key form
# (status: active | legacy | revoked) and the same revoked-in-trust
# footgun guard.
#
# Why a NixOS variant (INSPR-73)
# ──────────────────────────────
# The HM module owns `~/.ssh/authorized_keys`. The NixOS variant owns
# `/etc/ssh/authorized_keys.d/<user>`. sshd reads BOTH (per the default
# `AuthorizedKeysFile %h/.ssh/authorized_keys /etc/ssh/authorized_keys.d/%u`),
# so the two are complementary, not competing — but until this module
# existed, the system-side keys were a raw `listOf str` with no status
# metadata and no shared keyring. That meant retiring a key (INSPR-76)
# required hand-editing every host. With this module, retirement is a
# single edit at the keyring (`status = "legacy"` → `"revoked"`, drop
# from trust preset) and the next rebuild on each host filters it out.
#
# Usage (consumer's NixOS configuration):
#
#   inspr.ssh.authorized = {
#     enable = true;
#     keys = {
#       "alice@laptop"    = "ssh-ed25519 AAAAC3...laptop";
#       "alice@workstation" = "ssh-ed25519 AAAAC3...workstation";
#       "bob@laptop"        = "ssh-ed25519 AAAAC3...bob";
#       "shared-rsa-pre-2026" = {
#         key    = "ssh-rsa AAAA... shared";
#         status = "legacy";
#         note   = "shared RSA pre-2026; retire after ed25519 rollout";
#       };
#     };
#     users.alice = {
#       trust = [ "alice@laptop" "alice@workstation" "shared-rsa-pre-2026" ];
#       force = true;                       # replace any injected keys entirely
#       extraKeys = [
#         "ssh-ed25519 AAAA... container-deploy"   # one-off, not in keyring
#       ];
#     };
#     users.bob = {                          # multi-user supported
#       trust = [ "bob@laptop" ];
#     };
#   };
#
# Multi-user
# ──────────
# Each user gets its own `trust` (alias subset from the shared `keys`
# keyring) plus optional `extraKeys` (raw strings for one-off cases that
# do not belong in the shared keyring — e.g. a host-local container's
# ed25519 used only by one node-red flow).
#
# `force` controls whether the rendered list is `lib.mkForce`'d. Use
# `force = true` on hosts where another module (typically a server-home
# / hokage profile) injects keys you do NOT want admitted (e.g. external
# operator keys on private/family hosts). Default is `false` — list
# merging via concatenation, which is the safer default when you are
# rolling this out additively.
#
# Status semantics (identical to HM module — see INSPR-77)
# ────────────────────────────────────────────────────────
#   - "active"  (default): admitted normally
#   - "legacy":  admitted; the audit-tag lives in the .nix declaration
#                (no comment-line decoration — `authorized_keys.d/<u>`
#                files are line-oriented strings with no comment support
#                in the NixOS option type)
#   - "revoked": NOT admitted. Throws at eval time if the alias is also
#                in any user's `trust`, catching the "I forgot to remove
#                from trust" footgun.
#
# What this module does NOT do
# ────────────────────────────
#   - Marker-block coexistence (the HM module's `authorized_keys` patching
#     story). Not needed here — `users.users.<u>.openssh.authorizedKeys.keys`
#     is itself the canonical declarative spot; module merging handles
#     additive extension cleanly. `force = true` is the explicit knob
#     when you want to defeat an upstream module's injection.
#   - Activation script (the HM module needs one because `home.file`
#     would symlink into /nix/store, breaking sshd's StrictModes).
#     NixOS renders `authorized_keys.d/<u>` natively via `users.users`.
#
# SPDX-License-Identifier: AGPL-3.0-only
# ─────────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  ...
}:

let
  cfg = config.inspr.ssh.authorized;

  # Same normalize helper as the HM module: bare-string form → canonical
  # `{ key; status; note; }` record. Lets `keys` accept both forms in
  # the same map without callers caring.
  normalizeKey =
    value:
    if builtins.isString value then
      {
        key = value;
        status = "active";
        note = null;
      }
    else
      value;

  # Look up a key by alias. Throws with full context on miss — silent
  # fall-through (admitting nothing for an unknown alias) would be a
  # security-relevant footgun (the host would just stop trusting that
  # alias without any visible failure). Same throw shape as the HM
  # module so the error UX is consistent across modules.
  keyByAlias =
    alias:
    let
      raw =
        cfg.keys.${alias} or (throw ''
          inspr.ssh.authorized (NixOS): alias "${alias}" listed in `users.<name>.trust` but not declared in `keys`.
          Declared aliases: ${toString (lib.attrNames cfg.keys)}
        '');
    in
    normalizeKey raw;

  # Render one alias to its rendered key string. Throws on revoked-in-trust
  # to catch the "I forgot to remove from trust" footgun. Status="legacy"
  # is admitted (the audit metadata stays in the .nix source — there is
  # no per-line comment surface in the NixOS option type, unlike the HM
  # module's authorized_keys file).
  renderAlias =
    alias:
    let
      meta = keyByAlias alias;
    in
    if meta.status == "active" || meta.status == "legacy" then
      meta.key
    else
      throw ''
        inspr.ssh.authorized (NixOS): alias "${alias}" is in some user's `trust`
        but its declaration has status = "revoked". Revoked keys MUST NOT be
        admitted — the whole point of the revoked status is "kept as
        historical record, no longer admitted."

        Either:
          (a) remove "${alias}" from every users.<name>.trust list (preferred —
              declaration stays in `keys` as an audit trail of past admittance), or
          (b) change status back to "active" / "legacy" if the revocation
              was premature.
      '';

  # Render the full key list for one user. Trust list is sorted at eval
  # time so equivalent inputs produce byte-identical output (no spurious
  # `nixos-rebuild diff` noise from re-ordered source lists). extraKeys
  # is appended as-is (these are the escape hatch for one-off raw keys
  # that do not belong in the shared keyring — always treated as
  # "active", no status machinery applies).
  renderUserKeys =
    userCfg:
    let
      sortedTrust = lib.sort (a: b: a < b) userCfg.trust;
      aliasKeys = map renderAlias sortedTrust;
    in
    aliasKeys ++ userCfg.extraKeys;

  # Per-user submodule shape. Each user gets its own trust subset, force
  # toggle, and extraKeys escape hatch.
  userOpts = {
    options = {
      trust = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Aliases (keys in the shared `inspr.ssh.authorized.keys` keyring)
          admitted to this user's `~/.ssh/authorized_keys` (rendered into
          `/etc/ssh/authorized_keys.d/<user>`). An alias listed here that
          is not declared in `keys` throws an evaluation error.

          Order does not matter — sorted before rendering so equivalent
          inputs produce byte-identical output.
        '';
        example = lib.literalExpression ''[ "alice@laptop" "alice@workstation" ]'';
      };

      force = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          If `true`, the rendered key list is wrapped in `lib.mkForce`
          so it REPLACES (not merges with) any other declaration of
          `users.users.<name>.openssh.authorizedKeys.keys` in the
          configuration. Use on hosts where another module — typically
          a server-home / hokage profile — injects keys you do NOT want
          admitted (e.g. external operator keys on private/family hosts).

          Default `false` — list merging via concatenation, which is the
          safer additive default during rollout.
        '';
      };

      extraKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Raw SSH public key strings appended to this user's
          `authorized_keys.d/<name>` AFTER the trust-resolved keys.
          Escape hatch for one-off keys that do not belong in the shared
          keyring (e.g. a host-local container's ed25519 used only by
          one service on this host). Always treated as `status = "active"`
          — no status machinery applies.

          If a key is shared by multiple hosts, prefer adding it to the
          shared keyring instead so the audit metadata + retirement
          workflow apply.
        '';
        example = lib.literalExpression ''
          [ "ssh-ed25519 AAAA... container-deploy@host1 (node-red flow)" ]
        '';
      };
    };
  };
in
{
  options.inspr.ssh.authorized = {
    enable = lib.mkEnableOption "declarative system-side SSH authorized_keys management via aliased key map";

    keys = lib.mkOption {
      # Same `either str submodule` shape as the HM module — keep API
      # symmetric so consumers can declare the keyring once (in a shared
      # file imported at both NixOS-scope AND HM-scope) and have both
      # modules consume it with no transformation.
      type = lib.types.attrsOf (
        lib.types.either lib.types.str (
          lib.types.submodule {
            options = {
              key = lib.mkOption {
                type = lib.types.str;
                description = ''
                  The full SSH public key string (the entire
                  `ssh-<type> <material> <comment>` line as it would
                  appear in `authorized_keys`).
                '';
              };
              status = lib.mkOption {
                type = lib.types.enum [
                  "active"
                  "legacy"
                  "revoked"
                ];
                default = "active";
                description = ''
                  Lifecycle status. See HM module for full semantics —
                  the NixOS variant honors the same enum but cannot
                  decorate the rendered output with `[legacy]` tags
                  (no comment-line surface in `authorized_keys.d/<u>`).
                  The audit trail lives in the .nix source.
                '';
              };
              note = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  Free-form annotation. Visible only in the .nix source
                  (NixOS authorized_keys.d files have no comment surface).
                '';
              };
            };
          }
        )
      );
      default = { };
      description = ''
        Shared SSH public-key keyring: alias → either a bare key string
        (simple form) or a `{ key; status?; note?; }` submodule (rich
        form). See module header for rich-form semantics.

        Declaring a key here does NOT admit it — that requires adding
        the alias to a `users.<name>.trust` list.

        Best practice: define this once in a `modules/shared/ssh-keyring.nix`
        plain-Nix file imported BOTH at NixOS-module scope (for this
        module) AND at HM scope (for the HM module). Single source of
        truth across both modules.
      '';
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule userOpts);
      default = { };
      description = ''
        Per-user trust configuration. Each user attribute name must
        match a `users.users.<name>` declared elsewhere in the system
        configuration (this module does NOT create users — it only
        configures their authorized_keys).

        Each entry: `{ trust; force?; extraKeys?; }`. See submodule
        option descriptions for details.
      '';
      example = lib.literalExpression ''
        {
          alice = {
            trust = [ "alice@laptop" "shared-rsa-pre-2026" ];
            force = true;
          };
          bob = {
            trust = [ "bob@laptop" ];
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Eval-time sanity: warn (do not fail) if `enable = true` but no
    # users are configured. Most likely a half-finished config; the user
    # forgot to populate `users`. Do not throw — empty `users` is also
    # valid (e.g. enabling the module on a host where the keyring is
    # defined but no user wants the system-side rendering yet).
    warnings = lib.optional (cfg.users == { }) ''
      inspr.ssh.authorized (NixOS): enabled but `users` is empty. No
      authorized_keys rendering will happen. If this is intentional,
      ignore this warning. Otherwise add at least one user entry like
      `inspr.ssh.authorized.users.<name>.trust = [ ... ]`.
    '';

    # Render each user's keys and assign to users.users.<name>.openssh.authorizedKeys.keys.
    # `lib.mapAttrs` preserves the user-name keys; the inner mkForce
    # logic respects each user's `force` toggle.
    users.users = lib.mapAttrs (
      _uname: ucfg:
      let
        rendered = renderUserKeys ucfg;
      in
      {
        openssh.authorizedKeys.keys =
          if ucfg.force then lib.mkForce rendered else rendered;
      }
    ) cfg.users;
  };
}
