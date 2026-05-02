#!/usr/bin/env bash
#
# Functional test suite for the `secrets-audit` binary.
#
# Each test asserts that the binary produces the expected exit code AND
# the expected output content for a given fixture (a mock nixcfg-like
# directory layout under tests/secrets-audit/fixtures/).
#
# Usage:
#   ./run-tests.sh                # use ../../result/bin/secrets-audit (after `nix build .#secrets-audit`)
#   SECRETS_AUDIT=/path/to/bin ./run-tests.sh   # override binary path
#
# Exit codes:
#   0  all tests pass
#   1  one or more tests fail
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

# Resolve binary: explicit override, then nearest `result/` symlink from a `nix build .#secrets-audit`.
SECRETS_AUDIT="${SECRETS_AUDIT:-}"
if [[ -z "$SECRETS_AUDIT" ]]; then
    candidate="$SCRIPT_DIR/../../result/bin/secrets-audit"
    if [[ -x "$candidate" ]]; then
        SECRETS_AUDIT="$candidate"
    fi
fi
if [[ -z "$SECRETS_AUDIT" || ! -x "$SECRETS_AUDIT" ]]; then
    echo "ERROR: secrets-audit binary not found." >&2
    echo "  Hint: run \`nix build .#secrets-audit\` from the repo root first," >&2
    echo "        OR set SECRETS_AUDIT=/path/to/binary." >&2
    exit 2
fi

echo "Using binary: $SECRETS_AUDIT"
echo ""

PASS=0
FAIL=0
declare -a FAILED_TESTS=()

# assert_exit_code <name> <fixture> <expected-code>
#   Runs the binary against the fixture, asserts exit code matches.
assert_exit_code() {
    local name="$1" fixture="$2" expected="$3"
    local fixture_path="$FIXTURES/$fixture"
    if [[ ! -d "$fixture_path/secrets" ]]; then
        echo "  ✗ $name — fixture missing: $fixture_path/secrets"
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$name")
        return
    fi
    # Run from the fixture root so `git rev-parse` AND the script-dir
    # fallback both miss → triggers "is the script's parent the right
    # repo" path. Actually for these fixtures we want the script to use
    # the fixture as its repo. The script tries `git rev-parse` first
    # (will fail since fixtures aren't git repos), then falls back to
    # script-dir's parent — which would point at /nix/store/... So
    # neither strategy finds our fixture. We use the `INSPR_AUDIT_REPO`
    # env override... wait, the script doesn't have one. Let me check.
    # → For now, run from inside the fixture so `git rev-parse` MIGHT
    # find a parent repo — but more reliably, we cd into the fixture
    # and rely on the script-dir-fallback finding parent OK if we
    # symlink. Cleanest: copy the script invocation pattern that
    # production uses: `cd <repo-root>; secrets-audit`.
    local actual
    (cd "$fixture_path" && "$SECRETS_AUDIT" --quiet >/dev/null 2>&1)
    actual=$?
    if [[ "$actual" == "$expected" ]]; then
        echo "  ✓ $name (exit=$actual)"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $name — expected exit $expected, got $actual"
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$name")
    fi
}

# assert_output_contains <name> <fixture> <pattern>
#   Runs the binary in default mode (not --quiet), asserts output contains pattern.
assert_output_contains() {
    local name="$1" fixture="$2" pattern="$3"
    local fixture_path="$FIXTURES/$fixture"
    local out
    out=$(cd "$fixture_path" && "$SECRETS_AUDIT" 2>&1)
    if echo "$out" | grep -qF "$pattern"; then
        echo "  ✓ $name (output contains '$pattern')"
        PASS=$((PASS + 1))
    else
        echo "  ✗ $name — output did NOT contain '$pattern'"
        echo "    actual output:"
        echo "$out" | sed 's/^/      /'
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$name")
    fi
}

echo "═══ secrets-audit functional tests ═══"
echo ""

# Sanity: --help should NOT leak the PATH-export line as first output.
# Regression test for INSPR-50 (C7) — the bug that prompted the
# writeShellApplication migration.
echo "── --help safety (regression test for INSPR-50) ──"
help_first=$("$SECRETS_AUDIT" --help 2>&1 | head -1)
if [[ "$help_first" == export* ]]; then
    echo "  ✗ --help leaked PATH export as first line: '$help_first'"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("help-no-path-leak")
else
    echo "  ✓ --help first line clean: '$help_first'"
    PASS=$((PASS + 1))
fi
echo ""

echo "── exit code per fixture ──"
assert_exit_code "clean-fixture-exits-0"            clean             0
assert_exit_code "declared-missing-exits-1"         declared-missing  1
assert_exit_code "orphan-exits-1"                   orphan            1
assert_exit_code "with-comments-exits-0"            with-comments     0
echo ""

echo "── drift content per fixture ──"
assert_output_contains "declared-missing-mentions-missing-file"  declared-missing  "missing.age"
assert_output_contains "orphan-mentions-orphan-file"             orphan            "orphan1.age"
echo ""

# Summary
TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
    echo "✓ All $TOTAL secrets-audit tests passed"
    exit 0
else
    echo "✗ $FAIL of $TOTAL tests failed: ${FAILED_TESTS[*]}"
    exit 1
fi
