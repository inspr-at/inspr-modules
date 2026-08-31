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
# When enabled, the module also installs the reserved
# `inspr-worker-doctrine` skill into every configured harness by default. Its
# bundle carries the canonical worker-attribution mirror and calendar-version
# doctrine from this exact inspr-modules revision. The managed path never uses
# `force`; an existing user-owned path therefore blocks activation rather than
# being replaced silently.
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
  cfg = config.inspr.agent-skills;

  bundledRoot = ../../skills;

  workerDoctrineName = "inspr-worker-doctrine";
  workerDoctrineSource = import ../../lib/worker-doctrine-bundle.nix {
    inherit pkgs;
    skillSource = ../../skills/inspr-worker-doctrine/SKILL.md;
    attributionSource = ../../AGENTS.md;
    versioningSource = ../../docs/AGENTS-VERSIONING.md;
  };
  # Home Manager accepts an immutable store path here. Keep the option value
  # shallow: the module-eval harness deep-sequences home.file and should not
  # recursively traverse the package-set metadata carried by a derivation.
  workerDoctrineSourcePath = "${workerDoctrineSource}";

  # Harness names a skill actually targets: its own subset when given,
  # otherwise every declared harness.
  targetsOf = skill: if skill.harnesses == null then lib.attrNames cfg.harnesses else skill.harnesses;

  # Assertions do not short-circuit evaluation. Render only targets that
  # name a declared harness so assertion messages surface instead of a
  # missing-attribute error from the home.file mapping.
  declaredTargetsOf = skill: lib.filter (h: lib.hasAttr h cfg.harnesses) (targetsOf skill);

  workerDoctrineTargets =
    if cfg.workerDoctrine.harnesses == null then
      lib.attrNames cfg.harnesses
    else
      cfg.workerDoctrine.harnesses;

  declaredWorkerDoctrineTargets = lib.filter (h: lib.hasAttr h cfg.harnesses) workerDoctrineTargets;

  skillEntries = lib.concatLists (
    lib.mapAttrsToList (
      skillName: skill:
      map (h: {
        name = "${cfg.harnesses.${h}}/${skillName}";
        value.source = skill.source;
      }) (declaredTargetsOf skill)
    ) cfg.skills
  );

  workerDoctrineEntries =
    lib.optionals (cfg.workerDoctrine.enable && !(lib.hasAttr workerDoctrineName cfg.skills))
      (
        map (h: {
          name = "${cfg.harnesses.${h}}/${workerDoctrineName}";
          value.source = workerDoctrineSourcePath;
        }) declaredWorkerDoctrineTargets
      );
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

    workerDoctrine = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install the reserved inspr-worker-doctrine skill. The bundle includes
          the canonical worker-attribution mirror and calendar-version doctrine
          from the same immutable inspr-modules revision. Disable only when an
          equivalent managed worker-doctrine surface is supplied separately.
        '';
      };

      harnesses = lib.mkOption {
        type = lib.types.nullOr (lib.types.listOf lib.types.str);
        default = null;
        description = ''
          Harness names that receive inspr-worker-doctrine. null means every
          declared harness, matching the default behavior of bundled skills.
        '';
        example = [
          "claude"
          "codex"
        ];
      };
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
                defaultText = lib.literalExpression "inspr-modules' bundled skills/<name>";
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
    }) cfg.skills
    ++ lib.optional cfg.workerDoctrine.enable {
      assertion = workerDoctrineTargets == declaredWorkerDoctrineTargets;
      message = ''
        inspr.agent-skills.workerDoctrine.harnesses references undeclared
        harness(es): ${toString (lib.subtractLists declaredWorkerDoctrineTargets workerDoctrineTargets)}.
        Declared harnesses: ${toString (lib.attrNames cfg.harnesses)}.
      '';
    }
    ++ lib.optional cfg.workerDoctrine.enable {
      assertion = !(lib.hasAttr workerDoctrineName cfg.skills);
      message = ''
        inspr.agent-skills.skills.${workerDoctrineName} is reserved for the
        canonical managed worker-doctrine bundle. Configure
        inspr.agent-skills.workerDoctrine instead; no user entry was replaced.
      '';
    };

    # No `force` is set. Home Manager refuses an unmanaged filesystem
    # collision instead of replacing a user-owned skill directory.
    home.file = lib.listToAttrs (skillEntries ++ workerDoctrineEntries);
  };
}
