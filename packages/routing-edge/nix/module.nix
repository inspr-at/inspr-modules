# NixOS module for the INSPR routing-edge compiler + Traefik file provider.
#
# Disabled by default. It never provisions certificates, never enrols an OIDC
# client, never opens a firewall port and never exposes the Traefik dashboard or
# API. Managed TLS material reaches only the managed service through systemd
# credentials. External mode emits no public TLS paths and passes upstream CA
# paths through for the existing process — this module never reads key content.
#
# SPDX-License-Identifier: AGPL-3.0-only
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.inspr.routingEdge;

  inherit (lib) types;

  pinned = import ./pinned.nix;

  serviceName = "inspr-routing-edge";
  runtimeDir = "/run/${serviceName}";
  staticConfig = "${runtimeDir}/static.yml";
  managedMode = "managed";
  externalMode = "external-file-provider";
  defaultProviderFile = "traefik/dynamic/inspr-routing-edge.yml";
  isManaged = cfg.deploymentMode == managedMode;
  isExternal = cfg.deploymentMode == externalMode;

  # systemd exposes LoadCredential= material here, owned by the (dynamic) unit
  # user with mode 0400. This is the only place the service can read TLS from.
  credentialsDir = "/run/credentials/${serviceName}.service";

  # A path string, never PEM content. The compiler enforces the same rule; this
  # type turns an inlined key into an eval-time failure instead of a store leak.
  absolutePath = types.addCheck types.str (
    value:
    lib.hasPrefix "/" value
    && !(lib.hasInfix "-----BEGIN" value)
    && !(lib.hasInfix "\n" value)
  ) // {
    description = "absolute filesystem path (never inline PEM content)";
  };

  upstreamOpts = {
    options = {
      url = lib.mkOption {
        type = types.str;
        example = "https://paimos.internal:8443";
        description = ''
          Origin-only upstream URL (`http`/`https`; no path, query, fragment or
          userinfo). Validated by the compiler before Traefik starts.
        '';
      };

      caFile = lib.mkOption {
        type = types.nullOr absolutePath;
        default = null;
        example = "/etc/inspr/tls/upstream-ca.crt";
        description = ''
          Optional CA bundle for verifying an `https` upstream. Passed to the
          managed service as a systemd credential. In external mode the path is
          emitted unchanged and must be readable by the existing Traefik unit.
        '';
      };
    };
  };

  # Kept lazy: when `publicTls` is null this attribute set is simply absent, so
  # the assertions below are what an operator sees — not an attribute-selection
  # error from deep inside `builtins.toJSON`.
  entrypointAddress = if cfg.entrypoint.address == null then ":443" else cfg.entrypoint.address;

  deploymentDocument =
    {
      entrypoint = { name = cfg.entrypoint.name; }
      // lib.optionalAttrs isManaged { address = entrypointAddress; };
      upstreams = lib.mapAttrs (
        app: upstream:
        { url = upstream.url; }
        // lib.optionalAttrs (upstream.caFile != null) {
          ca_file =
            if isManaged then "${credentialsDir}/${caCredentialName app}" else upstream.caFile;
        }
      ) cfg.upstreams;
    }
    // lib.optionalAttrs isManaged {
      loopback_http_fixture = cfg.loopbackHttpFixture;
    }
    // lib.optionalAttrs (isManaged && cfg.publicTls != null) {
      public_tls = {
        cert_file = "${credentialsDir}/public-tls-cert";
        key_file = "${credentialsDir}/public-tls-key";
      };
    }
    // lib.optionalAttrs isExternal {
      mode = externalMode;
      certificate_resolver = cfg.external.certificateResolver;
      resource_namespace = cfg.external.resourceNamespace;
    };

  deploymentFile = pkgs.writeText "${serviceName}-deployment.json" (
    builtins.toJSON deploymentDocument
  );

  externalFragment = pkgs.runCommand "${serviceName}-external-fragment" { } ''
    mkdir -p "$out/generated"
    ${cfg.package}/bin/inspr-routing-edge-compile \
      --contract ${cfg.contractFile} \
      --deployment ${deploymentFile} \
      --output-dir "$out/generated"
    mv "$out/generated/dynamic.yml" "$out/fragment.yml"
    test ! -e "$out/generated/static.yml"
  '';

  caCredentialName = app: "upstream-ca-${app}";

  credentialNameOk = name: builtins.match "[a-zA-Z0-9][a-zA-Z0-9_-]*" name != null;

  addressPattern = "(127\\.0\\.0\\.1|localhost)?:[0-9]{1,5}";
  addressValid = builtins.match addressPattern entrypointAddress != null;
  entryPort =
    if addressValid then lib.toIntBase10 (lib.last (lib.splitString ":" entrypointAddress)) else null;
  portInRange = entryPort != null && entryPort >= 1 && entryPort <= 65535;
  needsPrivilegedPort = portInRange && entryPort < 1024;

  # `version` is the derivation attribute nixpkgs actually sets; `meta.version`
  # generally does not exist, so checking it would mean never checking at all.
  detectedTraefikVersion =
    if cfg.traefikPackage == null then null else cfg.traefikPackage.version or null;
  traefikVersionMatches = detectedTraefikVersion == pinned.traefikVersion;
  reportedTraefikVersion =
    if !isManaged then
      "<consumer-owned>"
    else if detectedTraefikVersion == null then
      "<undetectable>"
    else
      detectedTraefikVersion;

  externalVersionMatches = cfg.external.existingTraefikVersion == pinned.traefikVersion;
  reportedExternalVersion =
    if cfg.external.existingTraefikVersion == null then
      "<unreported>"
    else
      cfg.external.existingTraefikVersion;

  selectorIdentifier = value:
    value != null && builtins.match "[A-Za-z][A-Za-z0-9_-]{0,32}" value != null;
  namespaceIdentifier = value:
    value != null && builtins.match "[A-Za-z][A-Za-z0-9_-]{0,47}" value != null;

  providerFileValid =
    cfg.external.providerFile != ""
    && !(lib.hasPrefix "/" cfg.external.providerFile)
    && lib.hasSuffix ".yml" cfg.external.providerFile
    && lib.all (part: part != "" && part != "." && part != "..") (
      lib.splitString "/" cfg.external.providerFile
    );

  loadCredentials =
    lib.optionals (cfg.publicTls != null) [
      "public-tls-cert:${cfg.publicTls.certFile}"
      "public-tls-key:${cfg.publicTls.keyFile}"
    ]
    ++ lib.mapAttrsToList (app: upstream: "${caCredentialName app}:${upstream.caFile}") (
      lib.filterAttrs (_: upstream: upstream.caFile != null) cfg.upstreams
    );
in
{
  options.services.inspr.routingEdge = {
    enable = lib.mkEnableOption ''
      the INSPR prefix-preserving routing edge (Traefik file provider). Managed
      mode starts a listener; external mode only installs one dynamic fragment.
      Neither opens a firewall port, provisions a certificate or enrols OIDC
    '';

    package = lib.mkOption {
      type = types.package;
      description = ''
        `inspr-routing-edge` compiler package, built by the caller from
        `packages/routing-edge/nix/default.nix`. No default: this module does
        not pin an INSPR source for you.
      '';
    };

    deploymentMode = lib.mkOption {
      type = types.enum [ managedMode externalMode ];
      default = managedMode;
      description = ''
        Closed deployment mode. `managed` retains the listener-owning service;
        `external-file-provider` installs one dynamic fragment for an existing,
        consumer-owned Traefik and creates no service or listener.
      '';
    };

    traefikPackage = lib.mkOption {
      type = types.nullOr types.package;
      default = null;
      example = lib.literalExpression "pkgs.traefik";
      description = ''
        Managed-mode caller-supplied Traefik package. It is forbidden and not
        required in external mode. Must match the file-provider syntax the
        compiler emits (Traefik ${pinned.traefikVersion},
        `${pinned.traefikSyntax}`). Other versions are not claimed to work; see
        `allowUnpinnedTraefik`.
      '';
    };

    allowUnpinnedTraefik = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Proceed when managed `traefikPackage.version` or external
        `existingTraefikVersion` is not exactly ${pinned.traefikVersion}, or is
        unknown. Compatibility then becomes the operator's claim.
      '';
    };

    contractFile = lib.mkOption {
      type = types.path;
      example = lib.literalExpression "./routing/contract.json";
      description = ''
        Public `inspr.routing/0.1-draft` contract JSON. World-readable in the
        Nix store; it must not contain operator secrets.
      '';
    };

    loopbackHttpFixture = lib.mkOption {
      type = types.bool;
      default = false;
      description = ''
        Loopback HTTP fixture mode for isolated tests. Requires a loopback
        entrypoint address and loopback upstreams, and forbids `publicTls`.
      '';
    };

    entrypoint = {
      name = lib.mkOption {
        type = types.str;
        default = "websecure";
        description = "Traefik entrypoint name (short identifier).";
      };

      address = lib.mkOption {
        type = types.nullOr types.str;
        default = if isManaged then ":443" else null;
        example = "127.0.0.1:8080";
        description = ''
          Managed-mode Traefik entrypoint bind address (`:443` when null): `:port`, `127.0.0.1:port` or
          `localhost:port`. A port below 1024 is bound with a narrowly scoped
          `CAP_NET_BIND_SERVICE`; anything else runs with no capabilities.
          Must remain null in external-file-provider mode.
        '';
      };
    };

    external = {
      certificateResolver = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "existing-acme";
        description = ''
          Name of a certificate resolver already defined by the consumer's
          Traefik static configuration. Required only in external mode.
        '';
      };

      resourceNamespace = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "inspr-example";
        description = ''
          Unique prefix for every generated Traefik object. The consumer owns
          collision avoidance across all dynamic providers.
        '';
      };

      providerFile = lib.mkOption {
        type = types.str;
        default = defaultProviderFile;
        description = ''
          Relative `/etc` path for the one generated fragment. It must end in
          `.yml` and contain no empty, `.` or `..` path segment. NixOS detects
          ownership conflicts with another `environment.etc` declaration.
        '';
      };

      existingTraefikVersion = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
        example = pinned.traefikVersion;
        description = ''
          Version reported by the consumer-owned Traefik. This is an operator
          assertion, not runtime inspection; exact compatibility remains pinned
          to ${pinned.traefikVersion} unless `allowUnpinnedTraefik` is enabled.
        '';
      };
    };

    publicTls = lib.mkOption {
      default = null;
      type = types.nullOr (
        types.submodule {
          options = {
            certFile = lib.mkOption {
              type = absolutePath;
              example = "/etc/inspr/tls/public.crt";
              description = ''
                Absolute host path to the public TLS certificate. Passed to the
                service as a systemd credential and read by Traefik at runtime
                only.
              '';
            };

            keyFile = lib.mkOption {
              type = absolutePath;
              example = "/etc/inspr/tls/public.key";
              description = ''
                Absolute host path to the TLS private key. Passed to the service
                as a systemd credential; the key is never read, imported or
                copied into the Nix store, and never appears in a log line.
              '';
            };
          };
        }
      );
      description = ''
        Managed-mode public HTTPS certificate references. Required unless
        `loopbackHttpFixture = true`, and forbidden in external mode. Paths only
        — inline PEM content is rejected by the option type.
      '';
    };

    upstreams = lib.mkOption {
      type = types.attrsOf (types.submodule upstreamOpts);
      default = { };
      example = lib.literalExpression ''
        {
          aithema.url = "https://aithema.internal:8443";
          paimos.url = "https://paimos.internal:8443";
        }
      '';
      description = ''
        Explicit upstream origins keyed by app id (`aithema`, `paimos`,
        `pharos`, `janus`). The compiler rejects unknown ids, disabled apps with
        an upstream, and enabled apps without one.
      '';
    };

    generatedDeployment = lib.mkOption {
      type = types.attrs;
      internal = true;
      default = { };
      description = ''
        The deployment document handed to the compiler, for inspection and pure
        evaluation tests. Contains paths and origins only — never key material.
      '';
    };

    generatedDeploymentFile = lib.mkOption {
      type = types.nullOr types.path;
      internal = true;
      default = null;
      description = ''
        Store path of the generated deployment document. Same content as
        `generatedDeployment`; also never key material.
      '';
    };

    generatedFragmentFile = lib.mkOption {
      type = types.nullOr types.str;
      internal = true;
      default = null;
      description = "Store path of the external dynamic fragment, or null in managed mode.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.upstreams != { };
        message = "services.inspr.routingEdge: at least one upstream must be declared when enabled.";
      }
      {
        assertion = lib.all credentialNameOk (lib.attrNames cfg.upstreams);
        message =
          "services.inspr.routingEdge.upstreams: app ids must be alphanumeric (with `-`/`_`)"
          + " so they can name a systemd credential. Got: "
          + "${lib.concatStringsSep ", " (lib.attrNames cfg.upstreams)}.";
      }
      {
        assertion = !isManaged || cfg.loopbackHttpFixture || cfg.publicTls != null;
        message =
          "services.inspr.routingEdge: publicTls.certFile and publicTls.keyFile are required"
          + " for public operation. Set them to absolute host paths, or set"
          + " loopbackHttpFixture = true for a loopback-only test edge.";
      }
      {
        assertion = !isManaged || !cfg.loopbackHttpFixture || cfg.publicTls == null;
        message =
          "services.inspr.routingEdge: loopbackHttpFixture = true must not declare publicTls;"
          + " the compiler rejects TLS files in fixture mode.";
      }
      {
        assertion = !isManaged || portInRange;
        message =
          "services.inspr.routingEdge.entrypoint.address: expected `:port`, `127.0.0.1:port`"
          + " or `localhost:port` with a port in 1-65535, got"
          + " \"${entrypointAddress}\".";
      }
      {
        assertion = !isManaged || !cfg.loopbackHttpFixture
          || lib.hasInfix "127.0.0.1:" entrypointAddress
          || lib.hasInfix "localhost:" entrypointAddress;
        message =
          "services.inspr.routingEdge: loopbackHttpFixture = true requires entrypoint.address"
          + " to bind loopback (127.0.0.1:port or localhost:port), got"
          + " \"${entrypointAddress}\".";
      }
      {
        assertion = !isManaged || cfg.allowUnpinnedTraefik || traefikVersionMatches;
        message =
          "services.inspr.routingEdge.traefikPackage: the compiler emits Traefik"
          + " ${pinned.traefikVersion} ${pinned.traefikSyntax} syntax, but the supplied package"
          + " reports version ${reportedTraefikVersion}. Supply a matching Traefik, or set"
          + " allowUnpinnedTraefik = true to take responsibility for the difference.";
      }
      {
        assertion = !isManaged || cfg.traefikPackage != null;
        message = "services.inspr.routingEdge.traefikPackage is required in managed mode.";
      }
      {
        assertion = !isExternal || cfg.traefikPackage == null;
        message =
          "services.inspr.routingEdge: external-file-provider mode forbids traefikPackage;"
          + " it does not launch a Traefik process.";
      }
      {
        assertion = !isExternal || cfg.publicTls == null;
        message =
          "services.inspr.routingEdge: external-file-provider mode forbids publicTls;"
          + " the existing Traefik owns public TLS.";
      }
      {
        assertion = !isExternal || !cfg.loopbackHttpFixture;
        message =
          "services.inspr.routingEdge: external-file-provider mode forbids"
          + " loopbackHttpFixture and never owns a listener.";
      }
      {
        assertion = !isExternal || cfg.entrypoint.address == null;
        message =
          "services.inspr.routingEdge: external-file-provider mode forbids"
          + " entrypoint.address; declare only the existing entrypoint name.";
      }
      {
        assertion = selectorIdentifier cfg.entrypoint.name;
        message = "services.inspr.routingEdge.entrypoint.name must be a short identifier.";
      }
      {
        assertion = !isExternal || selectorIdentifier cfg.external.certificateResolver;
        message = "services.inspr.routingEdge.external.certificateResolver must name an existing resolver.";
      }
      {
        assertion = !isExternal || namespaceIdentifier cfg.external.resourceNamespace;
        message = "services.inspr.routingEdge.external.resourceNamespace must be a unique short identifier.";
      }
      {
        assertion = !isExternal || providerFileValid;
        message = "services.inspr.routingEdge.external.providerFile must be a safe relative /etc path ending in .yml.";
      }
      {
        assertion = !isExternal || cfg.allowUnpinnedTraefik || externalVersionMatches;
        message =
          "services.inspr.routingEdge.external.existingTraefikVersion: generated syntax targets"
          + " ${pinned.traefikVersion}, but the consumer reports ${reportedExternalVersion}."
          + " Report the matching version or set allowUnpinnedTraefik = true to own compatibility.";
      }
      {
        assertion = isExternal
          || (cfg.external.certificateResolver == null && cfg.external.resourceNamespace == null
            && cfg.external.existingTraefikVersion == null
            && cfg.external.providerFile == defaultProviderFile);
        message = "services.inspr.routingEdge.external selector/version options are incompatible with managed mode.";
      }
    ];

    warnings = lib.optional (
      cfg.allowUnpinnedTraefik
      && ((isManaged && !traefikVersionMatches) || (isExternal && !externalVersionMatches))
    ) (
      "services.inspr.routingEdge: using Traefik "
      + (if isManaged then reportedTraefikVersion else reportedExternalVersion)
      + " while the"
      + " generated configuration targets ${pinned.traefikVersion}"
      + " (${pinned.traefikSyntax}). Compatibility is unverified by this module."
    );

    services.inspr.routingEdge.generatedDeployment = deploymentDocument;
    services.inspr.routingEdge.generatedDeploymentFile = deploymentFile;
    services.inspr.routingEdge.generatedFragmentFile =
      if isExternal then externalFragment + "/fragment.yml" else null;

    environment.etc = lib.optionalAttrs isExternal {
      ${cfg.external.providerFile}.source = externalFragment + "/fragment.yml";
    };

    systemd.services.${serviceName} = lib.mkIf isManaged {
      description = "INSPR routing edge (Traefik file provider, prefix-preserving)";
      documentation = [ "https://github.com/inspr-at/inspr-modules/tree/main/packages/routing-edge" ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      # Compile first: an invalid contract/deployment pair fails the unit before
      # any listener exists. Findings go to stderr; no secret is echoed.
      preStart = ''
        ${cfg.package}/bin/inspr-routing-edge-compile \
          --contract ${cfg.contractFile} \
          --deployment ${deploymentFile} \
          --output-dir ${runtimeDir}
      '';

      script = ''
        exec ${cfg.traefikPackage}/bin/traefik --configFile=${staticConfig}
      '';

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;

        # Generated configuration is derived state, regenerated on every start.
        RuntimeDirectory = serviceName;
        RuntimeDirectoryMode = "0700";
        # `static.yml` is written with an absolute `providers.file.filename`;
        # this keeps any relative reference resolving inside the runtime dir too.
        WorkingDirectory = runtimeDir;
        UMask = "0077";

        # The only route to TLS material. ReadOnlyPaths would make a root-owned
        # 0600 key visible but still unreadable to the DynamicUser identity;
        # systemd credentials are installed for the unit's own user instead.
        LoadCredential = loadCredentials;

        AmbientCapabilities = lib.optionals needsPrivilegedPort [ "CAP_NET_BIND_SERVICE" ];
        CapabilityBoundingSet = if needsPrivilegedPort then [ "CAP_NET_BIND_SERVICE" ] else [ "" ];

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [ "@system-service" ];
        SystemCallErrorNumber = "EPERM";

        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
