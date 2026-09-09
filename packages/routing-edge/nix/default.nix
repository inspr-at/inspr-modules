# Public reusable package for the INSPR routing-edge compiler.
#
# The caller supplies a pinned `pkgs` and an immutable `insprSource` (a path or
# a store path). Nothing is fetched here: no nixpkgs, no Traefik, no network at
# build or run time.
#
# The installed tree reproduces the repository-relative layout
# (`packages/routing-edge/...` + `contracts/routing/validate.py`) because
# `routing_edge.compile` resolves the routing validator via
# `Path(__file__).resolve().parents[3] / "contracts" / "routing"`. Keeping that
# layout is why no packaging hook inside `compile.py` is needed.
#
# SPDX-License-Identifier: AGPL-3.0-only
{
  pkgs,
  insprSource,
}:

let
  inherit (pkgs) lib python3 stdenv makeWrapper;

  pinned = import ./pinned.nix;

  sourceRoot =
    if builtins.isPath insprSource || lib.isStorePath insprSource then
      insprSource
    else
      throw "inspr-routing-edge: insprSource must be an immutable path or store path (no unpinned fetch)";

  root = toString sourceRoot;

  # Only the public compiler and its one validator dependency. Everything else
  # in the umbrella repository — doctrine, doctrine-private, other contracts,
  # fixtures, playbooks, .git — stays out of the build source. Directories are
  # listed explicitly so that ancestors of a kept file are traversed; omitting
  # them silently prunes the whole subtree.
  keepDirs = [
    "contracts"
    "contracts/routing"
    "packages"
    "packages/routing-edge"
    "packages/routing-edge/routing_edge"
  ];

  keepFiles = [
    "contracts/routing/validate.py"
    "packages/routing-edge/LICENSE"
    "packages/routing-edge/generate.py"
  ];

  keepTrees = [ "packages/routing-edge/routing_edge/" ];

  src = lib.cleanSourceWith {
    name = "inspr-routing-edge-source";
    src = sourceRoot;
    filter =
      path: _type:
      let
        rel = lib.removePrefix (root + "/") (toString path);
        base = baseNameOf rel;
      in
      path == root
      || (
        base != "__pycache__"
        && base != ".gitignore"
        && !lib.hasSuffix ".pyc" base
        && (
          lib.elem rel keepDirs
          || lib.elem rel keepFiles
          || lib.any (tree: lib.hasPrefix tree rel) keepTrees
        )
      );
  };
in
# Name-only derivation on purpose: this packaging change does not mint a release
# coordinate for the compiler. Version-bearing metadata stays with whatever
# scheme the repository already publishes.
stdenv.mkDerivation {
  name = "inspr-routing-edge";

  inherit src;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/packages/routing-edge" "$out/contracts/routing" "$out/bin"
    mkdir -p "$out/share/doc/inspr-routing-edge"

    cp -r "$src/packages/routing-edge/routing_edge" "$out/packages/routing-edge/"
    cp "$src/packages/routing-edge/generate.py" "$out/packages/routing-edge/"
    cp "$src/contracts/routing/validate.py" "$out/contracts/routing/"
    cp "$src/packages/routing-edge/LICENSE" "$out/share/doc/inspr-routing-edge/LICENSE"

    chmod -R u+w "$out/packages/routing-edge" "$out/contracts/routing"

    makeWrapper ${python3}/bin/python3 "$out/bin/inspr-routing-edge-compile" \
      --add-flags "$out/packages/routing-edge/generate.py"

    runHook postInstall
  '';

  doCheck = false;
  doInstallCheck = true;

  # Fails the build if the Nix-side pin drifts from the compiler's own constant,
  # and proves the installed command resolves its validator import outside any
  # repository checkout.
  installCheckPhase = ''
    runHook preInstallCheck

    grep -qx 'PINNED_TRAEFIK_VERSION = "${pinned.traefikVersion}"' \
      "$out/packages/routing-edge/routing_edge/deployment.py"
    grep -qx 'PINNED_TRAEFIK_SYNTAX = "${pinned.traefikSyntax}"' \
      "$out/packages/routing-edge/routing_edge/deployment.py"

    ( cd / && "$out/bin/inspr-routing-edge-compile" --help >/dev/null )

    runHook postInstallCheck
  '';

  passthru = { inherit pinned; };

  meta = with lib; {
    description = "INSPR prefix-preserving routing-edge compiler (Traefik ${pinned.traefikVersion} file provider)";
    longDescription = ''
      Compiles an `inspr.routing/0.1-draft` contract plus bounded operator
      deployment inputs into Traefik ${pinned.traefikVersion} file-provider
      configuration. Prefixes are preserved; no identity is injected; no TLS
      key material is read at build or evaluation time.
    '';
    homepage = "https://github.com/inspr-at/inspr-modules/tree/main/packages/routing-edge";
    license = licenses.agpl3Only;
    mainProgram = "inspr-routing-edge-compile";
    platforms = platforms.all;
  };
}
