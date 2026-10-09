# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/agent-skills.test.nix
#
# Module-eval tests for `inspr.agent-skills`.
#
# Scope: option shapes, multi-harness home.file rendering, per-skill
# harness subsetting, the managed worker-doctrine surface, and the assertion
# set (empty skills, absolute harness path, undeclared harness reference,
# reserved-name collision). Skill sources resolve to the repo's bundled
# skills/; the worker doctrine is a derivation that carries canonical files.
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  module = ../../modules/home-manager/agent-skills.nix;

  bundledShipNext = ../../skills/ship-next;
  bundledProductGauntlet = ../../skills/product-gauntlet;

  tests = [
    {
      name = "disabled module produces no home.file entry";
      assertion =
        let
          r = evalModule {
            module = module;
            config = { };
          };
        in
        r.success && (r.config.home.file or { }) == { };
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
        &&
          lib.attrNames files == [
            ".claude/skills/inspr-worker-doctrine"
            ".claude/skills/ship-next"
            ".codex/skills/inspr-worker-doctrine"
            ".codex/skills/ship-next"
          ]
        && files.".claude/skills/ship-next".source == bundledShipNext
        && files.".codex/skills/ship-next".source == bundledShipNext
        && lib.hasPrefix "/nix/store/" files.".claude/skills/inspr-worker-doctrine".source
        &&
          files.".claude/skills/inspr-worker-doctrine".source
          == files.".codex/skills/inspr-worker-doctrine".source
        && !(files.".claude/skills/inspr-worker-doctrine" ? force)
        && !(files.".codex/skills/inspr-worker-doctrine" ? force);
    }

    {
      name = "existing product-gauntlet installation remains intact";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills = {
              enable = true;
              skills.product-gauntlet = { };
            };
          };
        in
        r.success
        && r.failedAssertions == [ ]
        && r.config.home.file.".claude/skills/product-gauntlet".source == bundledProductGauntlet
        && r.config.home.file.".codex/skills/product-gauntlet".source == bundledProductGauntlet
        && lib.hasAttr ".claude/skills/inspr-worker-doctrine" r.config.home.file
        && lib.hasAttr ".codex/skills/inspr-worker-doctrine" r.config.home.file;
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
        &&
          lib.attrNames r.config.home.file == [
            ".claude/skills/inspr-worker-doctrine"
            ".claude/skills/ship-next"
            ".codex/skills/inspr-worker-doctrine"
          ];
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
        && lib.elem ".gemini/skills/ship-next" (lib.attrNames r.config.home.file)
        && lib.elem ".gemini/skills/inspr-worker-doctrine" (lib.attrNames r.config.home.file);
    }

    {
      name = "worker doctrine can target a declared harness subset";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills = {
              enable = true;
              skills.ship-next = { };
              workerDoctrine.harnesses = [ "codex" ];
            };
          };
        in
        r.success
        && r.failedAssertions == [ ]
        && !(lib.hasAttr ".claude/skills/inspr-worker-doctrine" r.config.home.file)
        && lib.hasAttr ".codex/skills/inspr-worker-doctrine" r.config.home.file;
    }

    {
      name = "worker doctrine can be explicitly disabled";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills = {
              enable = true;
              skills.ship-next = { };
              workerDoctrine.enable = false;
            };
          };
        in
        r.success
        && r.failedAssertions == [ ]
        &&
          lib.attrNames r.config.home.file == [
            ".claude/skills/ship-next"
            ".codex/skills/ship-next"
          ];
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
              skills.ship-next.harnesses = [
                "claude"
                "cursor"
              ];
            };
          };
        in
        r.success
        && r.failedAssertions != [ ]
        # The declared harness still renders; only the undeclared one is
        # filtered out of the mapping so the assertion message can surface.
        &&
          lib.attrNames r.config.home.file == [
            ".claude/skills/inspr-worker-doctrine"
            ".claude/skills/ship-next"
            ".codex/skills/inspr-worker-doctrine"
          ];
    }

    {
      name = "reserved worker-doctrine skill fails instead of being overwritten";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-skills = {
              enable = true;
              skills.inspr-worker-doctrine.source = bundledShipNext;
            };
          };
        in
        r.success
        && r.failedAssertions != [ ]
        && r.config.home.file.".claude/skills/inspr-worker-doctrine".source == bundledShipNext
        && r.config.home.file.".codex/skills/inspr-worker-doctrine".source == bundledShipNext;
    }
  ];

in
runTests "agent-skills" tests
