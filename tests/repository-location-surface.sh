#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

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

if grep -Fq -e '$HOME/'Code -e '~/'Code "$inspr_cli"; then
  printf 'inspr CLI contains an operator-specific workspace default\n' >&2
  exit 1
fi

printf 'repository locations verified: canonical organization with configurable checkout paths\n'
