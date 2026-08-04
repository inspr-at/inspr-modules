# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/agent-skills.test.nix
#
# Module-eval tests for `inspr.agent-skills`.
#
# Scope: option shapes, multi-harness home.file rendering, per-skill
# harness subsetting, and the assertion set (empty skills, absolute
# harness path, undeclared harness reference). Sources resolve to the
# repo's bundled skills/ — plain paths, safe for the harness's deepSeq.
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  module = ../../modules/home-manager/agent-skills.nix;

  bundledShipNext = ../../skills/ship-next;

  tests = [
    {
      name = "disabled module produces no home.file entry";
      assertion =
        let r = evalModule { module = module; config = { }; };
        in r.success && (r.config.home.file or { }) == { };
    }

    {
      name = "bundled skill renders into every default harness";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills = {
              enable = true;
              skills.ship-next = { };
            };
          };
          files = r.config.home.file;
        in
        r.success
        && r.failedAssertions == [ ]
        && lib.attrNames files == [ ".claude/skills/ship-next" ".codex/skills/ship-next" ]
        && files.".claude/skills/ship-next".source == bundledShipNext
        && files.".codex/skills/ship-next".source == bundledShipNext;
    }

    {
      name = "per-skill harnesses list restricts rendering to that subset";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills = {
              enable = true;
              skills.ship-next.harnesses = [ "claude" ];
            };
          };
        in
        r.success
        && r.failedAssertions == [ ]
        && lib.attrNames r.config.home.file == [ ".claude/skills/ship-next" ];
    }

    {
      name = "extra declared harness receives skills too";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills = {
              enable = true;
              harnesses.gemini = ".gemini/skills";
              skills.ship-next = { };
            };
          };
        in
        r.success
        && r.failedAssertions == [ ]
        && lib.elem ".gemini/skills/ship-next" (lib.attrNames r.config.home.file);
    }

    {
      name = "enable with no skills fails its assertion";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills.enable = true;
          };
        in
        r.success && r.failedAssertions != [ ];
    }

    {
      name = "absolute harness path fails its assertion";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills = {
              enable = true;
              harnesses.claude = "/etc/claude/skills";
              skills.ship-next = { };
            };
          };
        in
        r.success && r.failedAssertions != [ ];
    }

    {
      name = "undeclared harness reference fails its assertion instead of throwing";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills = {
              enable = true;
              skills.ship-next.harnesses = [ "claude" "cursor" ];
            };
          };
        in
        r.success
        && r.failedAssertions != [ ]
        # The declared harness still renders; only the undeclared one is
        # filtered out of the mapping so the assertion message can surface.
        && lib.attrNames r.config.home.file == [ ".claude/skills/ship-next" ];
    }
  ];

in
runTests "agent-skills" tests
