#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
license_file="$repo_root/LICENSE"
expected_hash="0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0"

if command -v sha256sum >/dev/null 2>&1; then
  actual_hash="$(sha256sum "$license_file")"
else
  actual_hash="$(shasum -a 256 "$license_file")"
fi
actual_hash="${actual_hash%% *}"

if [[ "$actual_hash" != "$expected_hash" ]]; then
  printf 'LICENSE is not the canonical AGPLv3 text\n' >&2
  exit 1
fi

legacy_license_token='M''IT'
legacy_license_pattern="(^|[^[:alnum:]_])${legacy_license_token}([^[:alnum:]_]|$)"
# Lowercase -r on purpose (INSPR-279): -R dereferences every symlink met
# during recursion, so the scan followed result/result-1 build artifacts
# into /nix/store (spurious hits, perf sink, machine-dependent outcome)
# and would loop-warn on the doctrine -> . self-symlink. -r scans only
# real files under the root.
if grep -rEIn --exclude-dir=.git -- "$legacy_license_pattern" "$repo_root"; then
  printf 'legacy project-license declaration remains\n' >&2
  exit 1
fi

surfaces=(
  README.md
  CHANGELOG.md
  flake.nix
  docs/AGENTS-DOMAIN-PPM.md
  modules/home-manager/agent-secrets.nix
  modules/home-manager/devenv-direnv-fix.nix
  modules/home-manager/git-atelier-credentials.nix
  modules/home-manager/paimos-config.nix
  modules/home-manager/ssh-authorized.nix
  modules/nixos/ssh-authorized.nix
  tests/module-eval/harness.nix
)

for surface in "${surfaces[@]}"; do
  grep -q 'AGPL-3.0-only' "$repo_root/$surface" || {
    printf '%s does not declare AGPL-3.0-only\n' "$surface" >&2
    exit 1
  }
done

for package in pkgs/inspr/default.nix pkgs/secrets-audit/default.nix; do
  grep -q 'license = lib.licenses.agpl3Only;' "$repo_root/$package" || {
    printf '%s does not expose AGPL-3.0-only metadata\n' "$package" >&2
    exit 1
  }
done

printf 'license surface verified: AGPL-3.0-only\n'
