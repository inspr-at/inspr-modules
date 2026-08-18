#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

surfaces=(
  README.md
  flake.nix
  commands/inspr.md
  pkgs/inspr/default.nix
  pkgs/inspr/inspr.sh
  pkgs/secrets-audit/default.nix
)

# 🔴 The strings below are the ASSERTION, not content. This test fails if any of
# them appears in a shipped surface. Do not "clean up" or obfuscate them to
# satisfy a scanner — removing them does not remove a leak, it removes the check
# that would have caught one. leak-guard exempts this file by path for exactly
# that reason.
deprecated_references=(
  "github:markus-barta/inspr-modules"
  "https://github.com/markus-barta/inspr"
  "ghcr.io/markus-barta/pharos"
)

for reference in "${deprecated_references[@]}"; do
  for surface in "${surfaces[@]}"; do
    if grep -Fq -- "$reference" "$repo_root/$surface"; then
      printf '%s contains deprecated operational reference: %s\n' "$surface" "$reference" >&2
      exit 1
    fi
  done
done

inspr_cli="$repo_root/pkgs/inspr/inspr.sh"
pharos_image="ghcr.io/inspr-at/pharos/pharosd:latest"

if [[ "$(grep -Fc -- "$pharos_image" "$inspr_cli")" -ne 2 ]]; then
  printf 'inspr CLI help and runtime default must both use %s\n' "$pharos_image" >&2
  exit 1
fi

grep -Fq -- "git clone https://github.com/inspr-at/inspr.git" "$inspr_cli" || {
  printf 'inspr CLI does not clone inspr from the canonical organization\n' >&2
  exit 1
}

grep -Fq -- "git clone https://github.com/markus-barta/nixcfg.git" "$inspr_cli" || {
  printf 'inspr CLI no longer preserves the intentional personal nixcfg location\n' >&2
  exit 1
}

printf 'repository locations verified: canonical organization with personal nixcfg preserved\n'
