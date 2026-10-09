# Pure module-evaluation tests for services.inspr.routingEdge.
#
# Covers the four states the acceptance criteria name: disabled, enabled and
# valid, enabled with missing inputs, and enabled with invalid configuration.
# Nothing here builds or activates a NixOS system, and nothing reads a key.
#
# SPDX-License-Identifier: AGPL-3.0-only
{ harness, lib }:

let
  inherit (harness) evalNixosModule runTests pkgs;

  repoRoot = ../..;

  routingEdgePackage = import ../../packages/routing-edge/nix {
    inherit pkgs;
    insprSource = repoRoot;
  };

  routingModule = ../../packages/routing-edge/nix/module.nix;
  pinned = import ../../packages/routing-edge/nix/pinned.nix;

  sampleContract = repoRoot + "/contracts/routing/fixtures/valid/combined-connected.json";

  traefikStub =
    { name, version ? null }:
    pkgs.runCommand name (lib.optionalAttrs (version != null) { inherit version; }) ''
      mkdir -p "$out/bin"
      printf '#!/bin/sh\necho "traefik stub" >&2\n' > "$out/bin/traefik"
      chmod +x "$out/bin/traefik"
    '';

  traefikPinned = traefikStub {
    name = "traefik-stub-pinned";
    version = pinned.traefikVersion;
  };
  traefikUnversioned = traefikStub { name = "traefik-stub-unversioned"; };

  # `sampleContract` is a store path, so its string carries context; a regex
  # actually uses keeps its dependency.
  contractRef = builtins.unsafeDiscardStringContext "${sampleContract}";

  credentialsDir = "/run/credentials/inspr-routing-edge.service";

  operatorCert = "/etc/inspr/tls/public.crt";
  operatorKey = "/etc/inspr/tls/public.key";

  baseUpstreams = {
    aithema.url = "https://aithema.example.test:8443";
    paimos.url = "https://paimos.example.test:8443";
    pharos.url = "https://pharos.example.test:8443";
    janus.url = "https://janus.example.test:8443";
  };

  loopbackUpstreams = {
    aithema.url = "http://127.0.0.1:19001";
    paimos.url = "http://127.0.0.1:19002";
    pharos.url = "http://127.0.0.1:19003";
    janus.url = "http://127.0.0.1:19004";
  };

  routingEdge = settings: { services.inspr.routingEdge = settings; };

  publicBase = {
    enable = true;
    package = routingEdgePackage;
    traefikPackage = traefikPinned;
    contractFile = sampleContract;
    publicTls = {
      certFile = operatorCert;
      keyFile = operatorKey;
    };
    upstreams = baseUpstreams;
  };

  loopbackBase = {
    enable = true;
    package = routingEdgePackage;
    traefikPackage = traefikPinned;
    contractFile = sampleContract;
    loopbackHttpFixture = true;
    entrypoint.address = "127.0.0.1:18080";
    entrypoint.name = "web";
    upstreams = loopbackUpstreams;
  };

  externalBase = {
    enable = true;
    deploymentMode = "external-file-provider";
    package = routingEdgePackage;
    contractFile = sampleContract;
    entrypoint.name = "existing-websecure";
    external = {
      certificateResolver = "existing-acme";
      resourceNamespace = "fixture-edge";
      providerFile = "traefik/dynamic/fixture-edge.yml";
      existingTraefikVersion = pinned.traefikVersion;
    };
    upstreams = baseUpstreams // {
      paimos = {
        url = "https://paimos.example.test:8443";
        caFile = "/etc/traefik/upstream-ca.crt";
      };
    };
  };

  evalOf = settings: evalNixosModule {
    module = routingModule;
    config = routingEdge settings;
  };

  disabled = evalNixosModule {
    module = routingModule;
    config = { };
  };
  valid = evalOf publicBase;
  loopback = evalOf loopbackBase;
  external = evalOf externalBase;

  # A single rendered blob per evaluation: if a private key path ever leaked
  # into any generated string, it shows up here.
  renderedUnit =
    r:
    let
      unit = r.service;
    in
    if unit == null then
      ""
    else
      (unit.preStart or "")
      + (unit.script or "")
      + (builtins.toJSON (unit.serviceConfig or { }))
      + (builtins.toJSON r.deployment);

  sc = r: r.service.serviceConfig;

  tests = [
    # ---- disabled by default -------------------------------------------------
    {
      name = "module with no configuration evaluates and defines no service";
      assertion = disabled.success && disabled.service == null && disabled.units == { };
    }
    {
      name = "disabled module needs no package, traefik or contract input";
      assertion = disabled.success && disabled.assertions == [ ] && disabled.deployment == { };
    }
    {
      name = "disabled module emits no warnings and opens no firewall port";
      assertion = disabled.success && disabled.warnings == [ ] && disabled.firewall == [ ];
    }

    # ---- external file-provider fragment -----------------------------------
    {
      name = "external mode evaluates without a managed Traefik package or service";
      assertion =
        external.success
        && external.failedAssertions == [ ]
        && external.service == null
        && external.units == { };
    }
    {
      name = "external mode installs exactly its named provider fragment";
      assertion =
        external.success
        && lib.attrNames external.etc == [ "traefik/dynamic/fixture-edge.yml" ]
        && external.etc."traefik/dynamic/fixture-edge.yml".source == external.fragment;
    }
    {
      name = "external deployment names existing selectors and carries no listener or public key";
      assertion =
        external.success
        && external.deployment.mode == "external-file-provider"
        && external.deployment.entrypoint == { name = "existing-websecure"; }
        && external.deployment.certificate_resolver == "existing-acme"
        && external.deployment.resource_namespace == "fixture-edge"
        && !(external.deployment ? public_tls)
        && !(external.deployment ? loopback_http_fixture)
        && external.deployment.upstreams.paimos.ca_file == "/etc/traefik/upstream-ca.crt"
        && !(lib.hasInfix credentialsDir (builtins.toJSON external.deployment));
    }
    {
      name = "external mode opens no firewall and loads no credentials";
      assertion =
        external.success
        && external.firewall == [ ]
        && !(lib.hasInfix "LoadCredential" (renderedUnit external));
    }
    {
      name = "external mode rejects managed listener and TLS inputs";
      assertion =
        let
          withAddress = evalOf (externalBase // { entrypoint = { name = "existing-websecure"; address = ":443"; }; });
          withTls = evalOf (externalBase // { publicTls = { certFile = operatorCert; keyFile = operatorKey; }; });
          withFixture = evalOf (externalBase // { loopbackHttpFixture = true; });
          withPackage = evalOf (externalBase // { traefikPackage = traefikPinned; });
        in
        lib.any (a: lib.hasInfix "forbids entrypoint.address" a.message) withAddress.failedAssertions
        && lib.any (a: lib.hasInfix "forbids publicTls" a.message) withTls.failedAssertions
        && lib.any (a: lib.hasInfix "forbids loopbackHttpFixture" a.message) withFixture.failedAssertions
        && lib.any (a: lib.hasInfix "forbids traefikPackage" a.message) withPackage.failedAssertions;
    }
    {
      name = "external mode requires selectors, namespace and reported compatible version";
      assertion =
        let
          missing = evalOf (
            externalBase
            // {
              external = {
                providerFile = "traefik/dynamic/fixture-edge.yml";
              };
            }
          );
        in
        lib.length missing.failedAssertions == 3;
    }
    {
      name = "external provider path cannot escape or ambiguously own a directory";
      assertion =
        let
          escaped = evalOf (
            externalBase
            // { external = externalBase.external // { providerFile = "traefik/../static.yml"; }; }
          );
        in
        lib.any (a: lib.hasInfix "safe relative /etc path" a.message) escaped.failedAssertions;
    }
    {
      name = "unknown mode and managed external selectors fail closed";
      assertion =
        let
          unknown = evalOf (publicBase // { deploymentMode = "hybrid"; });
          mixed = evalOf (
            publicBase
            // {
              external = {
                certificateResolver = "existing-acme";
                resourceNamespace = "fixture-edge";
                providerFile = "traefik/dynamic/fixture-edge.yml";
                existingTraefikVersion = pinned.traefikVersion;
              };
            }
          );
        in
        !unknown.success
        && lib.any (a: lib.hasInfix "incompatible with managed mode" a.message)
          mixed.failedAssertions;
    }
    {
      name = "external version mismatch requires explicit compatibility ownership";
      assertion =
        let
          mismatch = evalOf (
            externalBase
            // {
              external = externalBase.external // { existingTraefikVersion = "3.7.11"; };
            }
          );
          accepted = evalOf (
            externalBase
            // {
              allowUnpinnedTraefik = true;
              external = externalBase.external // { existingTraefikVersion = "3.7.11"; };
            }
          );
        in
        lib.any (a: lib.hasInfix "consumer reports 3.7.11" a.message) mismatch.failedAssertions
        && accepted.failedAssertions == [ ]
        && lib.any (w: lib.hasInfix "3.7.11" w) accepted.warnings;
    }

    # ---- enabled and valid ---------------------------------------------------
    {
      name = "valid public configuration evaluates with no failed assertion or warning";
      assertion = valid.success && valid.failedAssertions == [ ] && valid.warnings == [ ];
    }
    {
      name = "valid configuration compiles the contract before starting traefik";
      assertion =
        lib.hasInfix "/bin/inspr-routing-edge-compile" valid.service.preStart
        && lib.hasInfix "--contract ${contractRef}" valid.service.preStart
        && lib.hasInfix "--output-dir /run/inspr-routing-edge" valid.service.preStart
        && lib.hasInfix "/bin/traefik --configFile=/run/inspr-routing-edge/static.yml" valid.service.script;
    }
    {
      name = "generated static config is resolved inside the runtime working directory";
      assertion = (sc valid).WorkingDirectory == "/run/inspr-routing-edge"
        && (sc valid).RuntimeDirectory == "inspr-routing-edge";
    }
    {
      name = "enabled configuration opens no firewall port";
      assertion = valid.firewall == [ ];
    }
    {
      name = "service runs unprivileged as a dynamic user with a hardened sandbox";
      assertion =
        (sc valid).DynamicUser == true
        && (sc valid).NoNewPrivileges == true
        && (sc valid).ProtectSystem == "strict"
        && (sc valid).ProtectHome == true
        && (sc valid).RestrictSUIDSGID == true;
    }

    # ---- TLS reaches the service as a runtime credential ---------------------
    {
      name = "public TLS is loaded as a systemd credential, not a store path";
      assertion =
        (sc valid).LoadCredential == [
          "public-tls-cert:${operatorCert}"
          "public-tls-key:${operatorKey}"
        ];
    }
    {
      name = "deployment document points traefik at the credential paths";
      assertion =
        valid.deployment.public_tls == {
          cert_file = "${credentialsDir}/public-tls-cert";
          key_file = "${credentialsDir}/public-tls-key";
        };
    }
    {
      name = "operator key path never reaches the generated deployment document";
      assertion = !(lib.hasInfix operatorKey (builtins.toJSON valid.deployment));
    }
    {
      name = "no PEM material appears anywhere in the rendered unit";
      assertion = !(lib.hasInfix "-----BEGIN" (renderedUnit valid));
    }
    {
      name = "an upstream CA bundle is loaded as a credential and referenced by path";
      assertion =
        let
          r = evalOf (
            publicBase
            // {
              upstreams = baseUpstreams // {
                paimos = {
                  url = "https://paimos.example.test:8443";
                  caFile = "/etc/inspr/tls/upstream-ca.crt";
                };
              };
            }
          );
        in
        r.success
        && r.failedAssertions == [ ]
        && lib.elem "upstream-ca-paimos:/etc/inspr/tls/upstream-ca.crt" (sc r).LoadCredential
        && r.deployment.upstreams.paimos.ca_file == "${credentialsDir}/upstream-ca-paimos";
    }

    # ---- privileged port binding --------------------------------------------
    {
      name = "port 443 is bound with a bounded CAP_NET_BIND_SERVICE";
      assertion =
        (sc valid).AmbientCapabilities == [ "CAP_NET_BIND_SERVICE" ]
        && (sc valid).CapabilityBoundingSet == [ "CAP_NET_BIND_SERVICE" ];
    }
    {
      name = "an unprivileged port drops every capability";
      assertion =
        let
          r = evalOf (publicBase // { entrypoint.address = ":8443"; });
        in
        r.success
        && r.failedAssertions == [ ]
        && (sc r).AmbientCapabilities == [ ]
        && (sc r).CapabilityBoundingSet == [ "" ];
    }

    # ---- loopback fixture ----------------------------------------------------
    {
      name = "loopback fixture evaluates with no TLS input at all";
      assertion =
        loopback.success
        && loopback.failedAssertions == [ ]
        && !(loopback.deployment ? public_tls)
        && (sc loopback).LoadCredential == [ ]
        && (sc loopback).AmbientCapabilities == [ ];
    }
    {
      name = "loopback fixture keeps the compiler's deployment contract shape";
      assertion =
        loopback.deployment.loopback_http_fixture == true
        && loopback.deployment.entrypoint == {
          name = "web";
          address = "127.0.0.1:18080";
        }
        && loopback.deployment.upstreams.janus == { url = "http://127.0.0.1:19004"; };
    }

    # ---- missing inputs ------------------------------------------------------
    {
      name = "public mode without TLS paths reports the assertion, not an eval error";
      assertion =
        let
          r = evalOf (removeAttrs publicBase [ "publicTls" ]);
        in
        r.success
        && lib.any (a: lib.hasInfix "publicTls.certFile and publicTls.keyFile" a.message)
          r.failedAssertions;
    }
    {
      name = "enabled without any upstream reports the assertion";
      assertion =
        let
          r = evalOf (removeAttrs publicBase [ "upstreams" ]);
        in
        r.success
        && lib.any (a: lib.hasInfix "at least one upstream" a.message) r.failedAssertions;
    }

    # ---- traefik compatibility ----------------------------------------------
    {
      name = "a traefik package with the pinned version passes the check silently";
      assertion = valid.warnings == [ ] && traefikPinned.version == pinned.traefikVersion;
    }
    {
      name = "an undeterminable traefik version fails the assertion instead of being ignored";
      assertion =
        let
          r = evalOf (publicBase // { traefikPackage = traefikUnversioned; });
        in
        r.success
        && lib.any (a: lib.hasInfix "<undetectable>" a.message) r.failedAssertions;
    }
    {
      name = "allowUnpinnedTraefik downgrades the version check to an explicit warning";
      assertion =
        let
          r = evalOf (
            publicBase
            // {
              traefikPackage = traefikUnversioned;
              allowUnpinnedTraefik = true;
            }
          );
        in
        r.success
        && r.failedAssertions == [ ]
        && lib.any (w: lib.hasInfix pinned.traefikVersion w) r.warnings;
    }

    # ---- invalid configuration ----------------------------------------------
    {
      name = "loopback fixture with publicTls reports the assertion";
      assertion =
        let
          r = evalOf (
            loopbackBase
            // {
              publicTls = {
                certFile = operatorCert;
                keyFile = operatorKey;
              };
            }
          );
        in
        r.success
        && lib.any (a: lib.hasInfix "must not declare" a.message) r.failedAssertions;
    }
    {
      name = "loopback fixture bound to a public address reports the assertion";
      assertion =
        let
          r = evalOf (loopbackBase // { entrypoint.address = ":18080"; });
        in
        r.success && lib.any (a: lib.hasInfix "bind loopback" a.message) r.failedAssertions;
    }
    {
      name = "a malformed entrypoint address reports the assertion";
      assertion =
        let
          r = evalOf (publicBase // { entrypoint.address = "0.0.0.0:443"; });
        in
        r.success
        && lib.any (a: lib.hasInfix "entrypoint.address" a.message) r.failedAssertions;
    }
    {
      name = "an out-of-range entrypoint port reports the assertion";
      assertion =
        let
          r = evalOf (publicBase // { entrypoint.address = ":70000"; });
        in
        r.success
        && lib.any (a: lib.hasInfix "1-65535" a.message) r.failedAssertions;
    }
    {
      name = "an upstream id that cannot name a credential reports the assertion";
      assertion =
        let
          r = evalOf (
            publicBase // { upstreams = { "bad id" = { url = "https://x.example.test"; }; }; }
          );
        in
        r.success && lib.any (a: lib.hasInfix "systemd credential" a.message) r.failedAssertions;
    }
    {
      name = "inline PEM in a key path is rejected by the option type";
      assertion =
        let
          r = evalOf (
            publicBase
            // {
              publicTls = {
                certFile = operatorCert;
                keyFile = "-----BEGIN PRIVATE KEY-----";
              };
            }
          );
        in
        !r.success;
    }
    {
      name = "a relative TLS path is rejected by the option type";
      assertion =
        let
          r = evalOf (
            publicBase
            // {
              publicTls = {
                certFile = "etc/inspr/tls/public.crt";
                keyFile = operatorKey;
              };
            }
          );
        in
        !r.success;
    }
  ];
in
(runTests "routing-edge-module" tests) // { externalFragment = external.fragment; }
