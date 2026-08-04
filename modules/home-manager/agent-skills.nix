# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║              INSPR — Declarative agent-skill provisioning                    ║
# ╚══════════════════════════════════════════════════════════════════════════════╝
#
# Materialize agent skills (directories with a SKILL.md at their root) into
# the skills directory of every configured CLI harness — Claude Code
# (~/.claude/skills/), Codex (~/.codex/skills/), and any future harness that
# adopts the same scan-a-directory convention — as read-only symlinks into
# /nix/store. Harnesses scan their skills path at session startup, read each
# subdirectory's SKILL.md frontmatter, and expose the skill as /<name>
# (Claude) or $<name> (Codex).
#
# WHY DECLARATIVE (vs. `npx skills add ...`, manual clones, or hand symlinks):
#   - Same skill set on every host that switches against the consumer flake.
#   - One source of truth per skill; per-harness copies cannot drift.
#   - Visible in flake source, auditable, rollbackable like any other HM file.
#   - Adding a harness is one attrset entry, not another round of symlinks.
#
# Skills come from two kinds of sources:
#   - BUNDLED: shipped in this repo under skills/<name>/. Naming a skill with
#     no explicit `source` uses the bundled copy.
#   - EXTERNAL: any path — typically a pinned fetchFromGitHub of an upstream
#     skill repo (e.g. anthropics/skills) — passed via `source`.
#
# Usage (consumer's home.nix):
#   imports = [ inputs.inspr-modules.homeManagerModules.agent-skills ];
#   inspr.agent-skills = {
#     enable = true;
#     skills = {
#       ship-next = { };                      # bundled, all harnesses
#       housekeeping = { };                   # bundled, all harnesses
#       frontend-design = {                   # external, Claude only
#         source = "${anthropicSkills}/skills/frontend-design";
#         harnesses = [ "claude" ];
#       };
#     };
#   };
#
# SPDX-License-Identifier: AGPL-3.0-only
#
{
  config,
  lib,
  ...
}:

let
  cfg = config.inspr.agent-skills;

  bundledRoot = ../../skills;

  # Harness names a skill actually targets: its own subset when given,
  # otherwise every declared harness.
  targetsOf = skill:
    if skill.harnesses == null then lib.attrNames cfg.harnesses else skill.harnesses;

  # Assertions do not short-circuit evaluation. Render only targets that
  # name a declared harness so assertion messages surface instead of a
  # missing-attribute error from the home.file mapping.
  declaredTargetsOf = skill:
    lib.filter (h: lib.hasAttr h cfg.harnesses) (targetsOf skill);
in
{
  options.inspr.agent-skills = {
    enable = lib.mkEnableOption "declarative agent-skill provisioning across CLI harnesses";

    harnesses = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        claude = ".claude/skills";
        codex = ".codex/skills";
      };
      description = ''
        Harness name → skills directory, relative to the home directory.
        Defaults cover Claude Code and Codex. Add an entry to provision the
        same skills into another harness; per-skill `harnesses` lists select
        a subset of these names.
      '';
      example = lib.literalExpression ''
        {
          claude = ".claude/skills";
          codex = ".codex/skills";
          gemini = ".gemini/skills";
        }
      '';
    };

    skills = lib.mkOption {
      description = ''
        Skills to install, keyed by skill name (the directory name harnesses
        scan; the skill is invoked as /<name>). Each skill needs a `source`
        directory containing SKILL.md at its root; omitting `source` uses the
        copy bundled with inspr-modules under skills/<name>/.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            options = {
              source = lib.mkOption {
                type = lib.types.path;
                default = bundledRoot + "/${name}";
                defaultText = lib.literalExpression ''inspr-modules' bundled skills/<name>'';
                description = ''
                  Directory containing the skill (SKILL.md at its root).
                  Default is the bundled copy of the same name; external
                  skills pass a pinned source, e.g.
                  "''${anthropicSkills}/skills/frontend-design".
                '';
              };

              harnesses = lib.mkOption {
                type = lib.types.nullOr (lib.types.listOf lib.types.str);
                default = null;
                description = ''
                  Harness names (keys of `inspr.agent-skills.harnesses`) this
                  skill installs into. null = all declared harnesses.
                '';
                example = [ "claude" ];
              };
            };
          }
        )
      );
      default = { };
      defaultText = lib.literalExpression "{ }";
      example = lib.literalExpression ''
        {
          ship-next = { };
          frontend-design = {
            source = "''${anthropicSkills}/skills/frontend-design";
            harnesses = [ "claude" ];
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (lib.attrNames cfg.skills) != [ ];
        message = ''
          inspr.agent-skills.enable = true requires at least one entry in
          inspr.agent-skills.skills. See `inspr.agent-skills.skills` for the
          expected shape.
        '';
      }
    ]
    ++ lib.mapAttrsToList (name: path: {
      assertion = path != "" && !(lib.hasPrefix "/" path);
      message = ''
        inspr.agent-skills.harnesses.${name} = "${path}" must be a non-empty
        path relative to the home directory (no leading "/").
      '';
    }) cfg.harnesses
    ++ lib.mapAttrsToList (name: skill: {
      assertion = targetsOf skill == declaredTargetsOf skill;
      message = ''
        inspr.agent-skills.skills."${name}".harnesses references undeclared
        harness(es): ${toString (lib.subtractLists (declaredTargetsOf skill) (targetsOf skill))}.
        Declared harnesses: ${toString (lib.attrNames cfg.harnesses)}.
      '';
    }) cfg.skills;

    home.file = lib.listToAttrs (
      lib.concatLists (
        lib.mapAttrsToList (
          skillName: skill:
          map (h: {
            name = "${cfg.harnesses.${h}}/${skillName}";
            value.source = skill.source;
          }) (declaredTargetsOf skill)
        ) cfg.skills
      )
    );
  };
}
