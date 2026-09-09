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
  version = "0.6.0";
  sourceRev = "902adaf2eb8e707f8e93c54f1c34f8688dbb54cd";
  lockDigest = "sha256:acd386661ff0c54ba827082a3872593bc6f50204e72eaaa0a2aeb3c487d68f02";

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
    hash = "sha256-E3dIlkW5fjpx3TDUbJ0ZPyYjfrmhQIT8WTB4ve/iLew=";
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
    runtimeSha256 = "1377489645b97e3a71dd30d46c9d193f26237eb9a14084fc593078bdefe22dec";
  };

  meta = {
    description = "Aithema requirements workspace service executable";
    homepage = "https://github.com/inspr-at/aithema";
    license = lib.licenses.agpl3Only;
    mainProgram = "aithema-workspace";
    platforms = lib.platforms.unix;
  };
}
