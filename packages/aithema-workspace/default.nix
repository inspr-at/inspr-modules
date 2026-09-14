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
  version = "0.7.0";
  sourceRev = "981e4d49b9360c430ae944afa4df29a37d536c76";
  lockDigest = "sha256:15a01b79899ad211a41e958c81bc728350967f81ad9a3f199477aea959f7f8b5";

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
    hash = "sha256-OFZd1OMSrvDpprHuuPBhMrsz6Cw2QI7DcJXqHAwjJfQ=";
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
    runtimeSha256 = "38565dd4e312aef0e9a6b1eeb8f06132bb33e82c36408ec37095ea1c0c2325f4";
  };

  meta = {
    description = "Aithema requirements workspace service executable";
    homepage = "https://github.com/inspr-at/aithema";
    license = lib.licenses.agpl3Only;
    mainProgram = "aithema-workspace";
    platforms = lib.platforms.unix;
  };
}
