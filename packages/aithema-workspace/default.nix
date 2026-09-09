# Aithema's supported service executable, packaged from its immutable public
# runtime release. Dependency fetches come from the release lockfile below;
# importNpmLock turns every `resolved` + `integrity` pair into an individual
# fixed-output Nix fetch rather than consulting a mutable npm installation.
#
# SPDX-License-Identifier: AGPL-3.0-only
{
  lib,
  stdenv,
  fetchurl,
  importNpmLock,
  makeWrapper,
  nodejs_24,
}:

let
  version = "0.5.0";
  sourceRev = "8a0b780a9361b1176b7a51d82b7c9eb90a9d70f3";
  lockDigest = "sha256:d5ad1d6e7504df4b001e655bcad15cf5c1b9b394a8efef4b1d0bff201386af5b";

  npmDeps = importNpmLock {
    npmRoot = ./.;
  };
in
stdenv.mkDerivation {
  pname = "aithema-workspace";
  inherit version npmDeps;

  src = fetchurl {
    name = "inspr-aithema-core-${version}.tgz";
    url = "https://github.com/inspr-at/aithema/releases/download/v${version}/inspr-aithema-core-${version}.tgz";
    hash = "sha256-UVfdc8ZUpidt/DvscCL10YySLLkLxCQ55cquPIM/2ao=";
  };

  sourceRoot = "package";
  nativeBuildInputs = [
    importNpmLock.npmConfigHook
    makeWrapper
    nodejs_24
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    package_dir="$out/lib/node_modules/@inspr/aithema-core"
    mkdir -p "$package_dir" "$out/bin"
    cp -R . "$package_dir"

    makeWrapper ${nodejs_24}/bin/node "$out/bin/aithema-workspace" \
      --add-flags "$package_dir/bin/aithema-workspace.js"

    runHook postInstall
  '';

  passthru.release = {
    inherit sourceRev lockDigest;
    runtimeSha256 = "5157dd73c654a6276dfc3bec7022f5d18c922cb90bc42439e5caae3c833fd9aa";
  };

  meta = {
    description = "Aithema requirements workspace service executable";
    homepage = "https://github.com/inspr-at/aithema";
    license = lib.licenses.agpl3Only;
    mainProgram = "aithema-workspace";
    platforms = lib.platforms.unix;
  };
}
