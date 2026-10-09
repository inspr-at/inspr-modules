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
  speechConfigFile =
    if cfg.speech == null then
      null
    else
      pkgs.writeText "aithema-workspace-speech-config.json" (builtins.toJSON {
        inherit (cfg.speech)
          kind
          providerId
          model
          allowedModels
          endpoint
          acceptedMediaTypes
          limits
          ;
      });
  speechArgs = lib.optionals (speechConfigFile != null) [
    "--speech-config"
    speechConfigFile
  ];
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

    speech = lib.mkOption {
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          kind = lib.mkOption {
            type = lib.types.enum [ "mock" "openai-compatible-transcription" ];
            default = "openai-compatible-transcription";
            description = "Aithema speech adapter kind; production uses the OpenAI-compatible transcription adapter.";
          };

          providerId = lib.mkOption {
            type = lib.types.str;
            description = "Operator provider registry identifier resolved by Aithema at runtime.";
          };

          model = lib.mkOption {
            type = lib.types.str;
            description = "Speech model identifier.";
          };

          allowedModels = lib.mkOption {
            type = lib.types.nonEmptyListOf lib.types.str;
            description = "Allowlist of speech model identifiers, including the selected model.";
          };

          endpoint = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Exact operator transcription endpoint; credentials must not be embedded in the URL.";
          };

          acceptedMediaTypes = lib.mkOption {
            type = lib.types.nonEmptyListOf lib.types.str;
            default = [ "audio/webm" "audio/mp4" ];
            description = "Browser audio media types accepted by the speech adapter.";
          };

          limits = lib.mkOption {
            type = lib.types.submodule {
              options = {
                maxAudioBytes = lib.mkOption {
                  type = lib.types.ints.between 1 4194304;
                  default = 2097152;
                  description = "Maximum uploaded audio size.";
                };
                maxRequestBytes = lib.mkOption {
                  type = lib.types.ints.between 1 4259840;
                  default = 2162688;
                  description = "Maximum speech request size.";
                };
                maxRecordingMs = lib.mkOption {
                  type = lib.types.ints.between 1 180000;
                  default = 60000;
                  description = "Maximum browser recording duration.";
                };
                maxDurationMs = lib.mkOption {
                  type = lib.types.ints.between 1 180000;
                  default = 60000;
                  description = "Maximum provider transcription duration.";
                };
                maxResponseBytes = lib.mkOption {
                  type = lib.types.ints.between 1 262144;
                  default = 65536;
                  description = "Maximum transcription response size.";
                };
                maxTranscriptChars = lib.mkOption {
                  type = lib.types.ints.between 1 8000;
                  default = 8000;
                  description = "Maximum transcript length accepted by the workspace.";
                };
              };
            };
            default = { };
            description = "Bounded speech request and response limits.";
          };
        };
      });
      default = null;
      description = ''
        Optional non-secret speech adapter settings. Null preserves protected
        runtime speech behavior and the service command exactly; speech remains
        disabled when it is absent there. When configured, these fields are
        rendered as a public Nix-store sidecar and provider credentials stay in
        Aithema's operator-owned runtime configuration.
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
      {
        assertion = cfg.speech == null || (cfg.package.supportsSpeechConfig or false);
        message = "services.inspr.aithemaWorkspace.package must advertise supportsSpeechConfig when speech is configured.";
      }
      {
        assertion = cfg.speech == null || cfg.speech.kind == "mock" || cfg.speech.endpoint != null;
        message = "services.inspr.aithemaWorkspace.speech requires an endpoint unless kind is mock.";
      }
      {
        assertion =
          cfg.speech == null
          || cfg.speech.endpoint == null
          || (!(lib.hasInfix "@" cfg.speech.endpoint)
            && !(lib.hasInfix "\n" cfg.speech.endpoint)
            && !(lib.hasInfix "\r" cfg.speech.endpoint));
        message = "services.inspr.aithemaWorkspace.speech.endpoint must not contain URL credentials or control characters.";
      }
      {
        assertion =
          cfg.speech == null
          || cfg.speech.limits.maxRequestBytes >= cfg.speech.limits.maxAudioBytes;
        message = "services.inspr.aithemaWorkspace.speech.limits.maxRequestBytes must be at least maxAudioBytes.";
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

        ExecStart = lib.escapeShellArgs (
          [
            "${lib.getExe cfg.package}"
            "--config"
            credentialPath
            "--shutdown-grace-ms"
            (toString shutdownGraceMs)
          ]
          ++ speechArgs
        );
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
