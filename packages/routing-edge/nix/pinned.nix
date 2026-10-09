# Single source of truth (Nix side) for the Traefik syntax the compiler emits.
#
# The compiler pins the same values in Python
# (`routing_edge/deployment.py`: PINNED_TRAEFIK_VERSION / PINNED_TRAEFIK_SYNTAX).
# `nix/default.nix` runs an install-time check that the two agree, so this file
# cannot silently drift away from the compiler.
#
# SPDX-License-Identifier: AGPL-3.0-only
{
  traefikVersion = "3.7.13";
  traefikSyntax = "file-provider-v3.7.13";
  traefikRelease = "https://github.com/traefik/traefik/releases/tag/v3.7.13";
  traefikOciImage = "docker.io/library/traefik";
  traefikOciIndexDigest = "sha256:f86a2cab1b5c649070c49f883c743dd32d8485a56e3368c5f93b9e91f1e91259";
  traefikOciLinuxAmd64Digest = "sha256:96780238b1bbda5a9bb997f4307ce69e798ad1cf6eb7f2dcc0a440823467d199";
}
