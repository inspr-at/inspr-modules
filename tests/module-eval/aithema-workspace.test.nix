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
  packageStubSpeech = pkgs.runCommand "aithema-workspace-speech" {
    meta.mainProgram = "aithema-workspace";
    passthru.supportsSpeechConfig = true;
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

  speechSettings = {
    kind = "openai-compatible-transcription";
    providerId = "operator-transcription";
    model = "whisper-fixture";
    allowedModels = [ "whisper-fixture" ];
    endpoint = "https://speech.example.invalid/v1/audio/transcriptions";
    acceptedMediaTypes = [ "audio/webm" "audio/mp4" ];
    limits = {
      maxAudioBytes = 1048576;
      maxRequestBytes = 1114112;
      maxRecordingMs = 30000;
      maxDurationMs = 30000;
      maxResponseBytes = 32768;
      maxTranscriptChars = 4000;
    };
  };

  speechEnabled = evalOf {
    enable = true;
    package = packageStubSpeech;
    configFile = "/run/secrets/aithema-workspace.json";
    speech = speechSettings;
  };

  service = valid.units."aithema-workspace";
  sc = service.serviceConfig;
  speechService = speechEnabled.units."aithema-workspace";
  speechSc = speechService.serviceConfig;
  expectedExecStart = lib.escapeShellArgs [
    "${lib.getExe packageStub}"
    "--config"
    "/run/credentials/aithema-workspace.service/runtime-config.json"
    "--shutdown-grace-ms"
    "10000"
  ];
  speechConfigPath = builtins.elemAt (builtins.match ".*--speech-config ([^ ]+)$" speechSc.ExecStart) 0;
  expectedSpeechConfigPath = pkgs.writeText "aithema-workspace-speech-config.json" (builtins.toJSON speechSettings);
  defaultSpeechSettings = {
    kind = "openai-compatible-transcription";
    providerId = "operator-transcription";
    model = "whisper-fixture";
    allowedModels = [ "whisper-fixture" ];
    endpoint = "https://speech.example.invalid/v1/audio/transcriptions";
    acceptedMediaTypes = [ "audio/webm" "audio/mp4" ];
    limits = {
      maxAudioBytes = 2097152;
      maxRequestBytes = 2162688;
      maxRecordingMs = 60000;
      maxDurationMs = 60000;
      maxResponseBytes = 65536;
      maxTranscriptChars = 8000;
    };
  };
  expectedDefaultSpeechConfigPath = pkgs.writeText "aithema-workspace-speech-config.json" (builtins.toJSON defaultSpeechSettings);

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
      name = "null speech preserves the existing command and credential wiring exactly";
      assertion =
        valid.success
        && sc.ExecStart == expectedExecStart
        && sc.LoadCredential == "runtime-config.json:/run/secrets/aithema-workspace.json";
    }
    {
      name = "enabled speech appends only the CLI sidecar argument and writes the plain public object";
      assertion =
        speechEnabled.success
        && speechSc.LoadCredential == sc.LoadCredential
        && lib.hasInfix "--speech-config ${speechConfigPath}" speechSc.ExecStart
        && speechConfigPath == toString expectedSpeechConfigPath
        && !(lib.hasInfix "/run/secrets/aithema-workspace.json" speechSc.ExecStart);
    }
    {
      name = "speech defaults remain bounded and the option rejects credentials or general fields";
      assertion =
        let
          defaults = evalOf {
            enable = true;
            package = packageStubSpeech;
            configFile = "/run/secrets/aithema-workspace.json";
            speech = {
              providerId = "operator-transcription";
              model = "whisper-fixture";
              allowedModels = [ "whisper-fixture" ];
              endpoint = "https://speech.example.invalid/v1/audio/transcriptions";
            };
          };
          credentials = evalOf {
            enable = true;
            package = packageStubSpeech;
            configFile = "/run/secrets/aithema-workspace.json";
            speech = speechSettings // { ${"api" + "Key"} = "redacted-fixture"; };
          };
          general = evalOf {
            enable = true;
            package = packageStubSpeech;
            configFile = "/run/secrets/aithema-workspace.json";
            speech = speechSettings // { executionLocation = "cloud"; };
          };
          defaultsConfigPath = builtins.elemAt (
            builtins.match ".*--speech-config ([^ ]+)$" defaults.units."aithema-workspace".serviceConfig.ExecStart
          ) 0;
        in
        defaults.success
        && defaultsConfigPath == toString expectedDefaultSpeechConfigPath
        && !credentials.success
        && !general.success;
    }
    {
      name = "speech capability, endpoint and limit invariants fail closed at evaluation";
      assertion =
        let
          legacyPackage = evalOf {
            enable = true;
            package = packageStub;
            configFile = "/run/secrets/aithema-workspace.json";
            speech = speechSettings;
          };
          missingEndpoint = evalOf {
            enable = true;
            package = packageStubSpeech;
            configFile = "/run/secrets/aithema-workspace.json";
            speech = speechSettings // { endpoint = null; };
          };
          urlCredentials = evalOf {
            enable = true;
            package = packageStubSpeech;
            configFile = "/run/secrets/aithema-workspace.json";
            speech = speechSettings // { endpoint = "https://user:password@speech.example.invalid/transcribe"; };
          };
          undersizedRequest = evalOf {
            enable = true;
            package = packageStubSpeech;
            configFile = "/run/secrets/aithema-workspace.json";
            speech = speechSettings // {
              limits = speechSettings.limits // { maxRequestBytes = 100; };
            };
          };
        in
        lib.any (a: lib.hasInfix "supportsSpeechConfig" a.message) legacyPackage.failedAssertions
        && lib.any (a: lib.hasInfix "requires an endpoint" a.message) missingEndpoint.failedAssertions
        && lib.any (a: lib.hasInfix "URL credentials" a.message) urlCredentials.failedAssertions
        && lib.any (a: lib.hasInfix "maxRequestBytes must be at least" a.message) undersizedRequest.failedAssertions;
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
