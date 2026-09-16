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
  version = "0.9.0";
  sourceRev = "5a004b302141196daff3fd578429390cbb3ea0e0";
  lockDigest = "sha256:090e19b9b5be534745ab3e3ab8bb0907284711e278794cab574902ae6c385467";

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
    hash = "sha256-FLijP5LdiJiVjOxSEFL7RGSpvc8sK3ZOJNuWDbriMVo=";
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

  passthru = {
    supportsSpeechConfig = true;
    release = {
      inherit sourceRev lockDigest;
      runtimeSha256 = "14b8a33f92dd8898958cec521052fb4464a9bdcf2c2b764e24db960dbae2315a";
    };
  };

  meta = {
    description = "Aithema requirements workspace service executable";
    homepage = "https://github.com/inspr-at/aithema";
    license = lib.licenses.agpl3Only;
    mainProgram = "aithema-workspace";
    platforms = lib.platforms.unix;
  };
}
