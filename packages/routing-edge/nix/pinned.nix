# Single source of truth (Nix side) for the Traefik syntax the compiler emits.
#
# The compiler pins the same values in Python
# (`routing_edge/deployment.py`: PINNED_TRAEFIK_VERSION / PINNED_TRAEFIK_SYNTAX).
# `nix/default.nix` runs an install-time check that the two agree, so this file
# cannot silently drift away from the compiler.
#
# SPDX-License-Identifier: AGPL-3.0-only
{
  traefikVersion = "3.7.12";
  traefikSyntax = "file-provider-v3.7.12";
}
