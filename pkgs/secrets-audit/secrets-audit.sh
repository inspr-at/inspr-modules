#!/usr/bin/env bash
#
# secrets-audit — drift detection between secrets/*.age and secrets.nix
# (See `--help` for the full description.)
#
set -euo pipefail

usage() {
    cat <<'USAGE'
secrets-audit — Detect drift between secrets/*.age and secrets/secrets.nix

Usage:
  secrets-audit              Print report; exit 1 on any drift
  secrets-audit --quiet      Print only on drift; exit 1 on any drift
  secrets-audit --json       Machine-readable output (requires jq)

Drift categories:
  declared-but-missing       declaration in secrets.nix has no file on disk
                              (probably planned secret not yet `agenix -e`'d,
                               OR stale declaration after a delete)
  on-disk-but-undeclared     file in secrets/ has no entry in secrets.nix
                              (orphan; unreachable by `agenix --rekey`,
                               won't decrypt to any host)

Exit codes:
  0  no drift
  1  drift detected
  2  usage / environment error
USAGE
}

# Color escapes — gated on stdout being a TTY, and respect NO_COLOR.
# (Audit-flagged: INSPR-60.)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    CYAN=$'\033[0;36m'
    RESET=$'\033[0m'
else
    RED='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

# Args
MODE="report" # report | quiet | json
case "${1:-}" in
"") ;;
--quiet) MODE="quiet" ;;
--json) MODE="json" ;;
-h | --help)
    usage
    exit 0
    ;;
*)
    echo "${RED}error:${RESET} unknown arg '$1' (try --help)" >&2
    exit 2
    ;;
esac

# Resolve repo root (the directory containing `secrets/secrets.nix`). Try in order:
#   1. $INSPR_AUDIT_REPO env override (explicit, useful for tests + scripted callers)
#   2. cwd itself if it has secrets/secrets.nix (the fixture/test case)
#   3. cwd's git toplevel (common case: invoked from anywhere inside the repo)
#   4. this script's own location's parent (absolute-path invocation fallback)
REPO=""
if [[ -n "${INSPR_AUDIT_REPO:-}" && -f "$INSPR_AUDIT_REPO/secrets/secrets.nix" ]]; then
    REPO="$INSPR_AUDIT_REPO"
elif [[ -f "$PWD/secrets/secrets.nix" ]]; then
    REPO="$PWD"
elif REPO_TOP="$(git rev-parse --show-toplevel 2>/dev/null)" && [[ -f "$REPO_TOP/secrets/secrets.nix" ]]; then
    REPO="$REPO_TOP"
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_PARENT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
    if [[ -f "$REPO_PARENT/secrets/secrets.nix" ]]; then
        REPO="$REPO_PARENT"
    fi
fi
if [[ -z "$REPO" ]]; then
    echo "${RED}error:${RESET} cannot locate repo (no secrets/secrets.nix found in cwd, git toplevel, or script-adjacent)" >&2
    echo "  Hint: set INSPR_AUDIT_REPO=/path/to/repo, or cd into the repo root first." >&2
    exit 2
fi

SECRETS_DIR="$REPO/secrets"
SECRETS_NIX="$SECRETS_DIR/secrets.nix"

# Build the disk set. Declarations include path prefix (e.g.
# "agents/shared/FOO.age"), so we capture the full relative path.
# `find -printf` is GNU-only; on BSD/macOS we fall back to sed-strip.
# (Audit-flagged: INSPR-59 was unused `disk_list`; removed.)
if disk_paths="$(find "$SECRETS_DIR" -name '*.age' -type f -printf '%P\n' 2>/dev/null)" &&
    [[ -n "$disk_paths" ]]; then
    : # GNU find branch succeeded
else
    disk_paths="$(find "$SECRETS_DIR" -name '*.age' -type f | sed "s|^$SECRETS_DIR/||")"
fi
disk_paths="$(echo "$disk_paths" | sort -u)"

# Declared: anything in quoted form `"...age"` in secrets.nix.
# Strip nix line-comments first (`# …` to end of line) so commented-out
# declarations (TODO/staged-but-disabled) don't show up as false drift.
# Block comments (/* … */) aren't used in this file — bail loudly if they
# appear so we know to extend this stripper.
if grep -q '/\*' "$SECRETS_NIX"; then
    echo "${RED}error:${RESET} secrets.nix uses block comments — audit script only handles line comments. Extend before trusting output." >&2
    exit 2
fi
declared="$(sed 's|#.*||' "$SECRETS_NIX" | grep -oE '"[^"]+\.age"' | tr -d '"' | sort -u)"

# Compute deltas
declared_missing="$(comm -23 \
    <(echo "$declared") \
    <(echo "$disk_paths"))"
disk_undeclared="$(comm -13 \
    <(echo "$declared") \
    <(echo "$disk_paths"))"

n_disk=$(echo "$disk_paths" | grep -c . || true)
n_decl=$(echo "$declared" | grep -c . || true)
n_dm=$(echo "$declared_missing" | grep -c . || true)
n_du=$(echo "$disk_undeclared" | grep -c . || true)
total_drift=$((n_dm + n_du))

# Output
if [[ "$MODE" == "json" ]]; then
    if ! command -v jq >/dev/null; then
        echo "${RED}error:${RESET} --json mode requires jq" >&2
        exit 2
    fi
    jq -n \
        --argjson n_disk "$n_disk" \
        --argjson n_decl "$n_decl" \
        --arg dm "$declared_missing" \
        --arg du "$disk_undeclared" \
        '{
          counts: { disk: $n_disk, declared: $n_decl, drift: (($dm|split("\n")|map(select(length>0))|length) + ($du|split("\n")|map(select(length>0))|length)) },
          declared_but_missing: ($dm|split("\n")|map(select(length>0))),
          on_disk_but_undeclared: ($du|split("\n")|map(select(length>0)))
        }'
    [[ $total_drift -eq 0 ]] && exit 0 || exit 1
fi

if [[ $total_drift -eq 0 ]]; then
    if [[ "$MODE" != "quiet" ]]; then
        echo "${GREEN}✓ secrets-audit: no drift${RESET} (${n_disk} on disk, ${n_decl} declared)"
    fi
    exit 0
fi

echo "${YELLOW}⚠ secrets-audit: drift detected${RESET} (${n_disk} on disk, ${n_decl} declared, ${total_drift} mismatches)"
echo ""

if [[ $n_dm -gt 0 ]]; then
    echo "${CYAN}Declared but missing on disk${RESET} ($n_dm):"
    echo "  ${YELLOW}probably:${RESET} planned secret not yet \`agenix -e\`'d, OR stale declaration after delete"
    echo "$declared_missing" | sed 's/^/  - /'
    echo ""
fi

if [[ $n_du -gt 0 ]]; then
    echo "${CYAN}On disk but undeclared in secrets.nix${RESET} ($n_du):"
    echo "  ${YELLOW}implication:${RESET} orphan — unreachable by \`agenix --rekey\`, won't decrypt to any host"
    echo "$disk_undeclared" | sed 's/^/  - /'
    echo ""
fi

exit 1
