# NixOS service wrapper for the public Aithema workspace runtime.
#
# The module deliberately does not model Aithema's runtime JSON as Nix options:
# production identity, memberships, provider credentials and policy remain in
# one operator-owned file outside the Nix store. systemd copies that file into
# its protected credential directory and the real CLI reads it from there.
#
# SPDX-License-Identifier: AGPL-3.0-only
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.inspr.aithemaWorkspace;
  serviceName = "aithema-workspace";
  statePath = "/var/lib/${cfg.stateDirectory}";
  credentialPath = "/run/credentials/${serviceName}.service/runtime-config.json";
  configuredFile = if cfg.configFile == null then "/invalid/missing-aithema-config" else cfg.configFile;
  shutdownGraceMs = cfg.shutdownGracePeriod * 1000;
  configPreflight = pkgs.writeText "aithema-workspace-config-preflight.mjs" ''
    import { readFileSync } from 'node:fs';

    const [configPath, expectedDataDir] = process.argv.slice(2);
    try {
      const runtimeConfig = JSON.parse(readFileSync(configPath, 'utf8'));
      if (runtimeConfig.dataDir !== expectedDataDir) throw new Error('data directory mismatch');
    } catch {
      console.error('Aithema runtime config is unreadable or does not name the managed persistent data directory; refusing to start.');
      process.exit(1);
    }
  '';
in
{
  options.services.inspr.aithemaWorkspace = {
    enable = lib.mkEnableOption "the Aithema requirements workspace service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/aithema-workspace { };
      defaultText = lib.literalExpression "pkgs.callPackage <inspr-modules/packages/aithema-workspace> { }";
      description = "Aithema workspace package to execute.";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/aithema-workspace.json";
      description = ''
        Absolute path to an operator-owned Aithema runtime JSON file. Keep this
        file outside the Nix store and protect it for the system manager.
        systemd presents a private copy to the service as a credential. Nix
        evaluation never reads, renders, logs or places its contents in argv;
        a runtime preflight checks only that `dataDir` matches managed state.

        Production configuration remains Aithema's own schema and must set
        `dataDir` to `/var/lib/${cfg.stateDirectory}`. Listening address,
        port, public origin/base path, identity, provider registry and policy
        are configured in that file and validated by Aithema itself.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "aithema";
      description = "Dedicated system user that owns the durable Aithema state directory.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "aithema";
      description = "Dedicated system group for the Aithema service.";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "^[A-Za-z0-9][A-Za-z0-9_.-]*$";
      default = "aithema-workspace";
      description = ''
        Directory name below `/var/lib` that systemd creates with durable,
        static ownership. The runtime config's `dataDir` must name the
        corresponding absolute path.
      '';
    };

    shutdownGracePeriod = lib.mkOption {
      type = lib.types.ints.between 0 300;
      default = 10;
      description = ''
        Maximum time Aithema drains in-flight HTTP work after SIGTERM. The
        service manager allows five additional seconds for the CLI to close
        SQLite and exit before enforcing termination.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.configFile != null;
        message = "services.inspr.aithemaWorkspace.configFile is required when the service is enabled.";
      }
      {
        assertion = cfg.configFile == null || lib.hasPrefix "/" cfg.configFile;
        message = "services.inspr.aithemaWorkspace.configFile must be an absolute runtime path.";
      }
      {
        assertion = cfg.configFile == null || !(lib.hasPrefix "${builtins.storeDir}/" cfg.configFile);
        message = "services.inspr.aithemaWorkspace.configFile must stay outside the Nix store.";
      }
      {
        assertion =
          cfg.configFile == null
          || (!(lib.hasInfix ":" cfg.configFile) && !(lib.hasInfix "\n" cfg.configFile));
        message = "services.inspr.aithemaWorkspace.configFile must not contain a colon or newline.";
      }
      {
        assertion = cfg.user != "root" && cfg.group != "root";
        message = "services.inspr.aithemaWorkspace must run under a dedicated non-root user and group.";
      }
    ];

    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = statePath;
      createHome = false;
    };

    systemd.services.${serviceName} = {
      description = "Aithema requirements workspace";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        DynamicUser = false;

        ExecStart = lib.escapeShellArgs [
          "${lib.getExe cfg.package}"
          "--config"
          credentialPath
          "--shutdown-grace-ms"
          (toString shutdownGraceMs)
        ];
        ExecStartPre = lib.escapeShellArgs [
          "${pkgs.nodejs_24}/bin/node"
          configPreflight
          credentialPath
          statePath
        ];
        LoadCredential = "runtime-config.json:${configuredFile}";

        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0750";
        WorkingDirectory = statePath;
        UMask = "0077";

        KillSignal = "SIGTERM";
        TimeoutStopSec = "${toString (cfg.shutdownGracePeriod + 5)}s";
        Restart = "on-failure";
        RestartSec = "5s";

        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ReadWritePaths = [ statePath ];
      };
    };
  };
}
