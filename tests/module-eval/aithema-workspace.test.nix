# Pure evaluation checks for the public Aithema NixOS service. They exercise
# disabled, enabled and fail-closed configurations without building NixOS or
# reading any runtime configuration file.
#
# SPDX-License-Identifier: AGPL-3.0-only
{ harness, lib }:

let
  inherit (harness) evalNixosModule runTests pkgs;

  module = ../../modules/nixos/aithema-workspace.nix;
  packageStub = pkgs.runCommand "aithema-workspace" {
    meta.mainProgram = "aithema-workspace";
  } ''
    mkdir -p "$out/bin"
    printf '#!/bin/sh\nexit 0\n' > "$out/bin/aithema-workspace"
    chmod +x "$out/bin/aithema-workspace"
  '';

  evalOf = settings: evalNixosModule {
    inherit module;
    config.services.inspr.aithemaWorkspace = settings;
  };

  disabled = evalNixosModule {
    inherit module;
    config = { };
  };

  valid = evalOf {
    enable = true;
    package = packageStub;
    configFile = "/run/secrets/aithema-workspace.json";
  };

  service = valid.units."aithema-workspace";
  sc = service.serviceConfig;

  tests = [
    {
      name = "disabled module defines no service, user, group or firewall rule";
      assertion =
        disabled.success
        && disabled.units == { }
        && disabled.config.users.users == { }
        && disabled.config.users.groups == { }
        && disabled.firewall == [ ];
    }
    {
      name = "enabled module creates a static dedicated owner and durable state directory";
      assertion =
        valid.success
        && valid.failedAssertions == [ ]
        && valid.config.users.users.aithema.isSystemUser
        && valid.config.users.users.aithema.group == "aithema"
        && valid.config.users.users.aithema.home == "/var/lib/aithema-workspace"
        && valid.config.users.groups ? aithema
        && sc.DynamicUser == false
        && sc.StateDirectory == "aithema-workspace"
        && sc.WorkingDirectory == "/var/lib/aithema-workspace";
    }
    {
      name = "service passes only a protected credential path to the real CLI";
      assertion =
        lib.hasInfix "/bin/aithema-workspace" sc.ExecStart
        && lib.hasInfix "--config /run/credentials/aithema-workspace.service/runtime-config.json" sc.ExecStart
        && lib.hasInfix "--shutdown-grace-ms 10000" sc.ExecStart
        && !(lib.hasInfix "/run/secrets/aithema-workspace.json" sc.ExecStart)
        && sc.LoadCredential == "runtime-config.json:/run/secrets/aithema-workspace.json";
    }
    {
      name = "runtime preflight enforces the managed persistent data directory without the source path";
      assertion =
        lib.hasInfix "/bin/node" sc.ExecStartPre
        && lib.hasInfix "/run/credentials/aithema-workspace.service/runtime-config.json" sc.ExecStartPre
        && lib.hasInfix "/var/lib/aithema-workspace" sc.ExecStartPre
        && !(lib.hasInfix "/run/secrets/aithema-workspace.json" sc.ExecStartPre);
    }
    {
      name = "service waits for networking, opens no firewall and preserves graceful shutdown";
      assertion =
        service.after == [ "network-online.target" ]
        && service.wants == [ "network-online.target" ]
        && service.wantedBy == [ "multi-user.target" ]
        && valid.firewall == [ ]
        && sc.KillSignal == "SIGTERM"
        && sc.TimeoutStopSec == "15s";
    }
    {
      name = "enabled service has a strict non-root sandbox with only durable state writable";
      assertion =
        sc.User == "aithema"
        && sc.Group == "aithema"
        && sc.NoNewPrivileges
        && sc.PrivateTmp
        && sc.ProtectHome
        && sc.ProtectSystem == "strict"
        && sc.ReadWritePaths == [ "/var/lib/aithema-workspace" ];
    }
    {
      name = "enabled service requires an explicit config file";
      assertion =
        let result = evalOf { enable = true; package = packageStub; };
        in lib.any (a: lib.hasInfix "configFile is required" a.message) result.failedAssertions;
    }
    {
      name = "runtime config path must be absolute, store-free and unambiguous";
      assertion =
        let
          relative = evalOf {
            enable = true;
            package = packageStub;
            configFile = "relative.json";
          };
          storeBacked = evalOf {
            enable = true;
            package = packageStub;
            configFile = "${builtins.storeDir}/fixture-config.json";
          };
          ambiguous = evalOf {
            enable = true;
            package = packageStub;
            configFile = "/run/secrets/aithema:workspace.json";
          };
        in
        lib.any (a: lib.hasInfix "absolute runtime path" a.message) relative.failedAssertions
        && lib.any (a: lib.hasInfix "outside the Nix store" a.message) storeBacked.failedAssertions
        && lib.any (a: lib.hasInfix "colon or newline" a.message) ambiguous.failedAssertions;
    }
    {
      name = "root service identity and unsafe state names fail closed";
      assertion =
        let
          rootOwned = evalOf {
            enable = true;
            package = packageStub;
            configFile = "/run/secrets/aithema-workspace.json";
            user = "root";
          };
          escapedState = evalOf {
            enable = true;
            package = packageStub;
            configFile = "/run/secrets/aithema-workspace.json";
            stateDirectory = "../escape";
          };
        in
        lib.any (a: lib.hasInfix "dedicated non-root" a.message) rootOwned.failedAssertions
        && !escapedState.success;
    }
  ];
in
runTests "aithema-workspace" tests
