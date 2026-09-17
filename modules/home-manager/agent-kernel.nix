# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              INSPR — Declarative kernel injection for CLI harnesses          ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Materialize `docs/AGENTS-KERNEL.md` into the global context-file slot of
# every configured CLI harness that does not follow Claude Code `@-ref`s.
# Pi is the default: it always loads `~/.pi/agent/AGENTS.md` and never
# expands `@./doctrine/docs/AGENTS-KERNEL.md` inside a repo `CLAUDE.md`.
#
# WHY DECLARATIVE (vs. a hand symlink or a copied `~/.pi/agent/AGENTS.md`):
#   - Same kernel bytes as this flake revision on every host that switches
#     against a consumer flake.
#   - One source of truth; per-harness copies cannot drift.
#   - Visible in flake source, auditable, rollbackable like any other HM file.
#   - Adding a harness is one attrset entry, not another round of symlinks.
#
# Usage (consumer's home.nix):
#   imports = [ inputs.inspr-modules.homeManagerModules.agent-kernel ];
#   inspr.agent-kernel.enable = true;
#   # optional:
#   # inspr.agent-kernel.harnesses.other = ".other/AGENTS.md";
#   # inspr.agent-kernel.source = ./concatenated-kernel.md;
#
# The managed path never uses `force`; an existing user-owned file therefore
# blocks activation rather than being replaced silently.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
{
  config,
  lib,
  ...
}:

let
  cfg = config.inspr.agent-kernel;

  # Keyed by target path so two harness names that share a slot render once.
  homeFiles = lib.mapAttrs' (_name: target: {
    name = target;
    value.source = cfg.source;
  }) cfg.harnesses;
in
{
  options.inspr.agent-kernel = {
    enable = lib.mkEnableOption "declarative INSPR kernel injection into CLI harnesses that do not follow CLAUDE.md @-refs";

    source = lib.mkOption {
      type = lib.types.path;
      default = ../../docs/AGENTS-KERNEL.md;
      defaultText = lib.literalExpression "inspr-modules' docs/AGENTS-KERNEL.md";
      description = ''
        Kernel file to materialize. Default is this flake's public kernel.
        Studio flakes may point at a concatenated file if they also load a
        private kernel; the atelier default stays identity-free.
      '';
    };

    harnesses = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        pi = ".pi/agent/AGENTS.md";
      };
      description = ''
        Harness name → context-file path relative to the home directory.
        Defaults cover Pi's global AGENTS.md, which Pi always loads and
        which is not replaced by a project CLAUDE.md. Adding a harness is
        one attrset entry.
      '';
      example = lib.literalExpression ''
        {
          pi = ".pi/agent/AGENTS.md";
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (lib.attrNames cfg.harnesses) != [ ];
        message = ''
          inspr.agent-kernel.enable = true requires at least one entry in
          inspr.agent-kernel.harnesses.
        '';
      }
    ]
    ++ lib.mapAttrsToList (name: path: {
      assertion = path != "" && !(lib.hasPrefix "/" path);
      message = ''
        inspr.agent-kernel.harnesses.${name} = "${path}" must be a non-empty
        path relative to the home directory (no leading "/").
      '';
    }) cfg.harnesses;

    # No `force` is set. Home Manager refuses an unmanaged filesystem
    # collision instead of replacing a user-owned context file.
    home.file = homeFiles;
  };
}
