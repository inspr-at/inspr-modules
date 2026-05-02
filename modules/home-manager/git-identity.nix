# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              INSPR — Multi-identity git config (HM module)                  ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Compose multiple git identities with `gitdir:` AND `hasconfig:remote.*.url:`
# includeIf rules. The repo's own remote URL picks the identity automatically
# — no per-host directory list to maintain.
#
# Usage (consumer's home.nix):
#
#   inspr.git-identity = {
#     enable = true;
#     default = "personal";
#     identities = {
#       personal = { name = "Jane Doe"; email = "jane@example.com"; };
#       work     = { name = "Jane Doe"; email = "jane@work.com";    };
#     };
#     contexts = {
#       work = {
#         identity = "work";
#         remoteUrlPatterns = [
#           "https://github.com/your-employer/**"
#           "**:your-employer/**"
#         ];
#         gitdirs = [ "~/Code/Work/" ];
#       };
#     };
#   };
#
# Pattern semantics gotcha (empirically verified):
#   `*` and `**` in `hasconfig:remote.*.url:` do NOT cross URL-component
#   boundaries (the `/` after scheme://host blocks the match). So for
#   HTTPS URLs use a pattern anchored on the host:
#     https://github.com/ORG/**       ✓ matches https://github.com/ORG/foo
#     **:ORG/**                       ✓ matches git@github.com:ORG/foo
#     **ORG/**                        ✓ matches SSH form, ✗ HTTPS form
#   Best practice: provide BOTH HTTPS and SSH patterns per context.
#
# Why git-native (not direnv): includeIf fires for EVERY git operation
# regardless of shell/IDE/agent context. direnv only fires in shells
# that load it.
#
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.inspr.git-identity;

  # Look up an identity by name; throw a useful error if it doesn't exist.
  identityByName =
    name:
    cfg.identities.${name} or (throw ''
      inspr.git-identity: identity "${name}" referenced but not declared.
      Declared identities: ${toString (lib.attrNames cfg.identities)}
    '');

  defaultId = identityByName cfg.default;

  # Render an identity as a [user] block — used as the body of an includeIf
  # path-target file so that a context-matched includeIf overrides the
  # global [user] section.
  mkIdentityFile =
    name: id:
    pkgs.writeText "git-identity-${name}" ''
      [user]
        name = ${id.name}
        email = ${id.email}
    '';

  # Per-context: render the identity to a store path, then build the list
  # of `{condition, path}` includes (one per gitdir + one per remote URL).
  mkContextIncludes =
    ctxName: ctx:
    let
      id = identityByName ctx.identity;
      idFile = toString (mkIdentityFile "${ctxName}" id);
    in
    (map (g: { condition = "gitdir:${g}"; path = idFile; }) ctx.gitdirs)
    ++ (map (r: { condition = "hasconfig:remote.*.url:${r}"; path = idFile; }) ctx.remoteUrlPatterns);
in
{
  options.inspr.git-identity = {
    enable = lib.mkEnableOption "multi-identity git config with gitdir + hasconfig:remote.*.url includeIf rules";

    default = lib.mkOption {
      type = lib.types.str;
      description = ''
        Name of the identity to use as the global default (when no context's
        gitdir or remoteUrlPatterns match). Must be a key in `identities`.
      '';
      example = "personal";
    };

    identities = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Git author/committer name (e.g. \"Jane Doe\")";
            };
            email = lib.mkOption {
              type = lib.types.str;
              description = "Git author/committer email (e.g. \"jane@example.com\")";
            };
          };
        }
      );
      description = ''
        Named git identities. The `default` option selects which one is
        the global default; contexts select the others by name.
      '';
      example = {
        personal = {
          name = "Jane Doe";
          email = "jane@example.com";
        };
        work = {
          name = "Jane Doe";
          email = "jane@work.com";
        };
      };
    };

    contexts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            identity = lib.mkOption {
              type = lib.types.str;
              description = "Name of the identity (key in `identities`) to switch to when this context matches.";
            };
            gitdirs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                List of directory roots that select this context. Use the
                git-config syntax — e.g. `~/Code/Work/` (trailing slash).
              '';
            };
            remoteUrlPatterns = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = ''
                List of `hasconfig:remote.*.url:` patterns that select this
                context. Per the semantics gotcha (see module header), provide
                BOTH HTTPS-anchored and SSH-anchored patterns per remote org.
              '';
            };
          };
        }
      );
      default = { };
      description = ''
        Per-context overrides. When a repo's gitdir matches one of a
        context's `gitdirs` OR any of the repo's remote URLs match one of
        the context's `remoteUrlPatterns`, that context's identity wins.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    programs.git = {
      enable = true;

      settings.user = {
        name = defaultId.name;
        email = defaultId.email;
      };

      includes = lib.flatten (lib.mapAttrsToList mkContextIncludes cfg.contexts);
    };
  };
}
