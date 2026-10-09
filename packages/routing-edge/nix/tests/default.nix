# Focused routing-edge Nix tests: Darwin package build + pure module evaluation.
#
#   nix-build  packages/routing-edge/nix/tests -A packageProof --arg pkgs 'import <PINNED> {}'
#   nix-instantiate --eval --strict --arg pkgs 'import <PINNED> {}' \
#     packages/routing-edge/nix/tests -A report
#
# `pkgs` is required on purpose: these tests pin nothing and must run against the
# caller's own nixpkgs. Nothing here builds or activates a NixOS system.
#
# SPDX-License-Identifier: AGPL-3.0-only
{
  pkgs,
  insprSource ? ../../../..,
}:

let
  lib = pkgs.lib;
  pinned = import ../pinned.nix;

  routingEdgePackage = import ../default.nix { inherit pkgs insprSource; };

  # Read straight from the caller's source tree, not from the package: the point
  # is to prove the installed command works on inputs it did not ship with.
  # Path concatenation, not string interpolation: each fixture is imported into
  # the store so the sandboxed proof can actually read it.
  sampleContract = insprSource + "/contracts/routing/fixtures/valid/combined-connected.json";
  sampleDeployment = insprSource + "/packages/routing-edge/fixtures/valid/combined-connected.deployment.json";
  # The repository ships no loopback contract fixture; its Python tests derive one
  # by rewriting `public_origin`, so do the same here.
  loopbackContract = pkgs.writeText "loopback-http.contract.json" (
    builtins.toJSON (
      builtins.fromJSON (builtins.readFile sampleContract)
      // {
        public_origin = {
          scheme = "http";
          host = "127.0.0.1";
        };
      }
    )
  );
  loopbackDeployment = insprSource + "/packages/routing-edge/fixtures/valid/loopback-http.deployment.json";

  # The repository's invalid fixtures are JSON-patch descriptors, so build the
  # rejected case here: the connected contract enables janus, this deployment
  # does not wire it.
  invalidDeployment = pkgs.writeText "missing-upstream.deployment.json" (
    builtins.toJSON {
      entrypoint = {
        name = "websecure";
        address = ":443";
      };
      public_tls = {
        cert_file = "/etc/inspr/tls/public.crt";
        key_file = "/etc/inspr/tls/public.key";
      };
      upstreams = {
        aithema.url = "https://aithema.example.test:8443";
        paimos.url = "https://paimos.example.test:8443";
        pharos.url = "https://pharos.example.test:8443";
      };
    }
  );

  externalDeployment = pkgs.writeText "external.deployment.json" (
    builtins.toJSON {
      mode = "external-file-provider";
      entrypoint.name = "existing-websecure";
      certificate_resolver = "existing-acme";
      resource_namespace = "fixture-edge";
      upstreams = {
        aithema.url = "https://aithema.example.test:8443";
        paimos = {
          url = "https://paimos.example.test:8443";
          ca_file = "/etc/traefik/upstream-ca.crt";
        };
        pharos.url = "https://pharos.example.test:8443";
        janus.url = "https://janus.example.test:8443";
      };
    }
  );

  # Stub Traefik packages. The module never runs them during evaluation; they
  # exist so the version check has something real to read (or, deliberately,
  # nothing to read).
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

  compilerStub = pkgs.runCommand "inspr-routing-edge-stub" { } ''
    mkdir -p "$out/bin"
    printf '#!/bin/sh\nexit 0\n' > "$out/bin/inspr-routing-edge-compile"
    chmod +x "$out/bin/inspr-routing-edge-compile"
  '';

  harness = import ./harness.nix { inherit lib pkgs; };

  moduleResult = import ./module.test.nix {
    inherit
      harness
      lib
      pkgs
      routingEdgePackage
      traefikPinned
      traefikUnversioned
      sampleContract
      ;
  };

  # Real NixOS module system, evaluated purely for a Linux host from Darwin.
  # Evaluation only — no system is built and nothing is activated.
  nixosEval = import ./nixos-eval.nix {
    inherit lib pkgs sampleContract;
    routingEdgePackage = compilerStub;
    traefikPackage = traefikPinned;
  };

  packageProof =
    pkgs.runCommand "inspr-routing-edge-package-proof"
      {
        nativeBuildInputs = [
          pkgs.coreutils
          pkgs.gnugrep
        ];
      }
      ''
        set -eu

        out_dir="$TMPDIR/public"
        loopback_dir="$TMPDIR/loopback"
        external_dir="$TMPDIR/external"
        mkdir -p "$out_dir" "$loopback_dir" "$external_dir"

        # Run from / so nothing can resolve through a repository checkout.
        cd /

        ${routingEdgePackage}/bin/inspr-routing-edge-compile \
          --contract ${sampleContract} \
          --deployment ${sampleDeployment} \
          --output-dir "$out_dir"

        test -f "$out_dir/dynamic.yml"
        test -f "$out_dir/static.yml"
        test -f "$out_dir/wiring-report.json"

        # Pinned syntax and prefix preservation.
        grep -q '${pinned.traefikVersion}' "$out_dir/dynamic.yml"
        grep -q 'passHostHeader: true' "$out_dir/dynamic.yml"
        ! grep -qi 'stripprefix' "$out_dir/dynamic.yml"
        ! grep -q 'Access-Control-Allow-Origin' "$out_dir/dynamic.yml"
        ! grep -q 'insecureSkipVerify' "$out_dir/dynamic.yml"

        # Generated denial and identity-header rules survive.
        grep -q 'inspr-deny-unpublished' "$out_dir/dynamic.yml"
        grep -q 'inspr-drop-forwarded-identity' "$out_dir/dynamic.yml"
        grep -q 'X-Forwarded-User' "$out_dir/dynamic.yml"

        # SSE stays streaming, not buffered.
        grep -q 'responseHeaderTimeout: "0s"' "$out_dir/dynamic.yml"
        ! grep -q 'buffering:' "$out_dir/dynamic.yml"

        # No dashboard or API surface in the static configuration, and the file
        # provider names dynamic.yml by absolute path.
        ! grep -qE '^(api|dashboard):' "$out_dir/static.yml"
        # write_outputs rewrites the file provider to an absolute, resolved path,
        # so traefik does not depend on its working directory to find dynamic.yml.
        grep -qE 'filename: "/.+/dynamic\.yml"' "$out_dir/static.yml"

        # TLS is referenced by path; no key material anywhere in the output.
        grep -q '/etc/inspr/tls/public.key' "$out_dir/dynamic.yml"
        ! grep -rq 'BEGIN .*PRIVATE KEY' "$out_dir"

        # Loopback fixture mode compiles without any TLS input.
        ${routingEdgePackage}/bin/inspr-routing-edge-compile \
          --contract ${loopbackContract} \
          --deployment ${loopbackDeployment} \
          --output-dir "$loopback_dir"
        ! grep -q 'certFile' "$loopback_dir/dynamic.yml"

        # External mode produces an independently installable fragment only.
        ${routingEdgePackage}/bin/inspr-routing-edge-compile \
          --contract ${sampleContract} \
          --deployment ${externalDeployment} \
          --output-dir "$external_dir"
        test -f "$external_dir/dynamic.yml"
        test ! -e "$external_dir/static.yml"
        grep -q 'fixture-edge-app-paimos' "$external_dir/dynamic.yml"
        grep -q 'certResolver: "existing-acme"' "$external_dir/dynamic.yml"
        grep -q 'rootCAs:' "$external_dir/dynamic.yml"
        grep -q '/etc/traefik/upstream-ca.crt' "$external_dir/dynamic.yml"
        ! grep -q 'certFile:' "$external_dir/dynamic.yml"

        # An invalid deployment fails closed and writes nothing.
        rejected_dir="$TMPDIR/rejected"
        mkdir -p "$rejected_dir"
        if ${routingEdgePackage}/bin/inspr-routing-edge-compile \
          --contract ${sampleContract} \
          --deployment ${invalidDeployment} \
          --output-dir "$rejected_dir" 2>"$TMPDIR/findings.txt"; then
          echo "expected the compiler to reject an invalid deployment" >&2
          exit 1
        fi
        test ! -f "$rejected_dir/dynamic.yml"
        grep -q 'MISSING_UPSTREAM' "$TMPDIR/findings.txt"

        # The build source carried only the public compiler and its validator.
        test -f ${routingEdgePackage}/contracts/routing/validate.py
        test ! -e ${routingEdgePackage}/doctrine
        test ! -e ${routingEdgePackage}/doctrine-private
        test ! -e ${routingEdgePackage}/packages/routing-edge/tests
        test ! -e ${routingEdgePackage}/packages/routing-edge/fixtures

        touch $out
      '';

  externalInstallProof =
    pkgs.runCommand "inspr-routing-edge-external-install-proof"
      { nativeBuildInputs = [ pkgs.gnugrep ]; }
      ''
        test -f ${moduleResult.externalFragment}
        grep -q 'fixture-edge-app-paimos' ${moduleResult.externalFragment}
        grep -q 'certResolver: "existing-acme"' ${moduleResult.externalFragment}
        ! grep -q 'certFile:' ${moduleResult.externalFragment}
        test ! -e ${builtins.dirOf moduleResult.externalFragment}/static.yml
        touch $out
      '';

  allFailed = moduleResult.failedTests ++ nixosEval.failedTests;

  report =
    if allFailed == [ ] then
      ''
        ✓ routing-edge nix checks evaluated clean

        Module (mocked harness): ${toString moduleResult.passed}/${toString moduleResult.total}
        Module (real NixOS eval): ${toString nixosEval.passed}/${toString nixosEval.total}

        Package build + installed-command proof is a separate build:
          nix-build packages/routing-edge/nix/tests -A packageProof
      ''
    else
      ''
        ✗ routing-edge nix checks failed

        ${lib.concatMapStringsSep "\n" (t: "  ✗ ${t}") allFailed}
      '';
in
{
  inherit
    routingEdgePackage
    moduleResult
    nixosEval
    packageProof
    externalInstallProof
    report
    ;
  ok = allFailed == [ ];
}
