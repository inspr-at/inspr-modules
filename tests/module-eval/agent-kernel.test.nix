# ─────────────────────────────────────────────────────────────────────────
# tests/module-eval/agent-kernel.test.nix
#
# Module-eval tests for `inspr.agent-kernel` (INSPR-445).
#
# Scope: disabled shape, default Pi slot, extra harnesses, custom source,
# extraSources, marker-only install, and the assertion set.
# ─────────────────────────────────────────────────────────────────────────
{ harness, lib }:

let
  inherit (harness) evalModule runTests;

  module = ../../modules/home-manager/agent-kernel.nix;
  publicKernel = ../../docs/AGENTS-KERNEL.md;
  customSource = ../../docs/AGENTS-INDEX.md;

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
      name = "enabled default renders Pi AGENTS.md from the public kernel without force";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-kernel.enable = true;
          };
          files = r.config.home.file;
        in
        r.success
        && r.failedAssertions == [ ]
        && lib.attrNames files == [ ".pi/agent/AGENTS.md" ]
        && files.".pi/agent/AGENTS.md".source == publicKernel
        && !(files.".pi/agent/AGENTS.md" ? force);
    }

    {
      name = "extra declared harness receives the same kernel";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-kernel = {
              enable = true;
              harnesses = {
                pi = ".pi/agent/AGENTS.md";
                other = ".other/AGENTS.md";
              };
            };
          };
          files = r.config.home.file;
        in
        r.success
        && r.failedAssertions == [ ]
        && lib.elem ".pi/agent/AGENTS.md" (lib.attrNames files)
        && lib.elem ".other/AGENTS.md" (lib.attrNames files)
        && files.".other/AGENTS.md".source == publicKernel;
    }

    {
      name = "custom source replaces the public kernel";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-kernel = {
              enable = true;
              source = customSource;
            };
          };
        in
        r.success
        && r.failedAssertions == [ ]
        && r.config.home.file.".pi/agent/AGENTS.md".source == customSource;
    }

    {
      name = "extraSources option accepts a path while disabled";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-kernel.extraSources = [ customSource ];
          };
        in
        r.success && (r.config.home.file or { }) == { };
    }

    {
      name = "marker-only install writes no replace home.file";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-kernel = {
              enable = true;
              harnesses = lib.mkForce { };
              markerHarnesses.codex = ".codex/AGENTS.md";
            };
          };
        in
        r.success
        && r.failedAssertions == [ ]
        && (r.config.home.file or { }) == { }
        && r.config.home.activation ? insprAgentKernelMarkers;
    }

    {
      name = "enable with no harnesses fails its assertion";
      assertion =
        let
          r = evalModule {
            module = module;
            config.inspr.agent-kernel = {
              enable = true;
              harnesses = lib.mkForce { };
            };
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
            config.inspr.agent-kernel = {
              enable = true;
              harnesses.pi = "/etc/pi/AGENTS.md";
            };
          };
        in
        r.success && r.failedAssertions != [ ];
    }
  ];

in
runTests "agent-kernel" tests
