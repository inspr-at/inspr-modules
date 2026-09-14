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
  version = "0.8.0";
  sourceRev = "fb5ac0239821a4efa9ae4930c1a0ec6545095498";
  lockDigest = "sha256:7d60f239a894971981efe9a8bb93e66b146f2cfbe1549751d83995e66bf748c0";

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
    hash = "sha256-Bz1Fp3aOt+8NfhZLItVFZzFmspNEC3SAjlnysYRsDSk=";
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
    runtimeSha256 = "073d45a7768eb7ef0d7e164b22d545673166b293440b74808e59f2b1846c0d29";
  };

  meta = {
    description = "Aithema requirements workspace service executable";
    homepage = "https://github.com/inspr-at/aithema";
    license = lib.licenses.agpl3Only;
    mainProgram = "aithema-workspace";
    platforms = lib.platforms.unix;
  };
}
