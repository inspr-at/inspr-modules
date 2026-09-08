# Real NixOS module-system evaluation of services.inspr.routingEdge.
#
# The mocked harness in `harness.nix` is fast but only knows the four options it
# declares; it cannot catch a serviceConfig key the real systemd module rejects.
# This file evaluates the module inside the actual NixOS module set and forces
# the rendered unit text.
#
# EVALUATION ONLY. Nothing is built and nothing is activated — running this on
# macOS never builds a NixOS system.
#
# SPDX-License-Identifier: AGPL-3.0-only
{
  lib,
  pkgs,
  routingEdgePackage,
  traefikPackage,
  sampleContract,
  nixosSystem ? "x86_64-linux",
}:

let
  evalConfig = import "${toString pkgs.path}/nixos/lib/eval-config.nix";

  evalNixos =
    settings:
    let
      evaluated = evalConfig {
        system = nixosSystem;
        modules = [
          ../module.nix
          (
            { ... }:
            {
              # Enough of a host to evaluate units without building anything.
              boot.isContainer = true;
              system.stateVersion = lib.trivial.release;
              services.inspr.routingEdge = settings;
            }
          )
        ];
      };

      # Only failing assertions get their message forced. Several stock NixOS
      # assertions build a message that throws unless the assertion is false
      # (`fileSystems` topological sort, for one), so forcing every message
      # would report a nixpkgs quirk as a routing-edge failure.
      failed = lib.filter (a: !a.assertion) evaluated.config.assertions;

      observable = {
        failedMessages = map (a: a.message) failed;
        warnings = evaluated.config.warnings;
        firewall = evaluated.config.networking.firewall.allowedTCPPorts;
        hasService = evaluated.config.systemd.services ? inspr-routing-edge;
        hasExternalFile = evaluated.config.environment.etc ? "traefik/dynamic/fixture-edge.yml";
        unitText =
          if evaluated.config.systemd.units ? "inspr-routing-edge.service" then
            evaluated.config.systemd.units."inspr-routing-edge.service".text
          else
            "";
      };

      result = builtins.tryEval (builtins.deepSeq observable observable);
    in
    if result.success then result.value // { success = true; } else {
      success = false;
      failedMessages = [ ];
      warnings = [ ];
      firewall = [ ];
      hasService = false;
      hasExternalFile = false;
      unitText = "";
    };

  operatorKey = "/etc/inspr/tls/public.key";

  publicSettings = {
    enable = true;
    package = routingEdgePackage;
    inherit traefikPackage;
    contractFile = sampleContract;
    publicTls = {
      certFile = "/etc/inspr/tls/public.crt";
      keyFile = operatorKey;
    };
    upstreams = {
      aithema.url = "https://aithema.example.test:8443";
      paimos.url = "https://paimos.example.test:8443";
      pharos.url = "https://pharos.example.test:8443";
      janus.url = "https://janus.example.test:8443";
    };
  };

  disabled = evalNixos { };
  enabled = evalNixos publicSettings;
  missingTls = evalNixos (removeAttrs publicSettings [ "publicTls" ]);
  external = evalNixos {
    enable = true;
    deploymentMode = "external-file-provider";
    package = routingEdgePackage;
    contractFile = sampleContract;
    entrypoint.name = "existing-websecure";
    external = {
      certificateResolver = "existing-acme";
      resourceNamespace = "fixture-edge";
      providerFile = "traefik/dynamic/fixture-edge.yml";
      existingTraefikVersion = "3.7.12";
    };
    upstreams = publicSettings.upstreams;
  };

  harness = import ./harness.nix { inherit lib pkgs; };
in
harness.runTests "routing-edge-nixos-eval" [
  {
    name = "real NixOS evaluation of a disabled module defines no unit";
    assertion = disabled.success && !disabled.hasService && disabled.failedMessages == [ ];
  }
  {
    name = "real NixOS evaluation renders a valid unit with no failed assertion";
    assertion = enabled.success && enabled.hasService && enabled.failedMessages == [ ];
  }
  {
    name = "rendered unit loads TLS as a credential and binds :443 with one capability";
    assertion =
      lib.hasInfix "LoadCredential=public-tls-key:${operatorKey}" enabled.unitText
      && lib.hasInfix "AmbientCapabilities=CAP_NET_BIND_SERVICE" enabled.unitText
      && lib.hasInfix "CapabilityBoundingSet=CAP_NET_BIND_SERVICE" enabled.unitText
      && lib.hasInfix "DynamicUser=true" enabled.unitText
      && lib.hasInfix "RuntimeDirectory=inspr-routing-edge" enabled.unitText;
  }
  {
    name = "rendered unit never inlines key material";
    assertion = !(lib.hasInfix "-----BEGIN" enabled.unitText);
  }
  {
    name = "real NixOS evaluation opens no firewall port";
    assertion = enabled.firewall == [ ];
  }
  {
    name = "real NixOS evaluation reports missing TLS as an assertion, not an eval error";
    assertion =
      missingTls.success
      && lib.any (m: lib.hasInfix "publicTls.certFile and publicTls.keyFile" m)
        missingTls.failedMessages;
  }
  {
    name = "real NixOS evaluation installs external fragment without defining another service";
    assertion =
      external.success
      && external.failedMessages == [ ]
      && external.hasExternalFile
      && !external.hasService
      && external.firewall == [ ];
  }
]
