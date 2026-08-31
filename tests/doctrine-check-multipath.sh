#!/usr/bin/env bash
# Focused doctrine-check contract (INSPR-323).
set -uo pipefail

SOURCE_ROOT="${1:?usage: doctrine-check-multipath.sh SOURCE_ROOT}"
CHECK="$SOURCE_ROOT/scripts/doctrine-check.sh"
BASH_UNDER_TEST="${DOCTRINE_TEST_BASH:-/bin/bash}"
REV_A="1111111111111111111111111111111111111111"
REV_B="2222222222222222222222222222222222222222"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/doctrine-check-multipath.XXXXXX")
TMP_ROOT=$(cd "$TMP_ROOT" && pwd -P)
trap 'chmod -R u+w "$TMP_ROOT" 2>/dev/null || true; rm -rf "$TMP_ROOT"' EXIT

failed=0
last_status=0
last_output="$TMP_ROOT/output"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failed=$((failed+1))
}

new_repo() {
  local name="$1" path="$TMP_ROOT/$1"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name "Doctrine Check Fixture"
  git -C "$path" config user.email "fixture@example.invalid"
  printf '%s\n' "$path"
}

add_gitlink() {
  local repo="$1" path="$2" url="$3" rev="$4"
  printf '[submodule "%s"]\n\tpath = %s\n\turl = %s\n' \
    "$path" "$path" "$url" >> "$repo/.gitmodules"
  git -C "$repo" update-index --add --cacheinfo 160000 "$rev" "$path"
  git -C "$repo" add .gitmodules
}

write_lock() {
  local repo="$1" name="$2" owner="$3" upstream="$4" rev="$5"
  printf '%s\n' \
    '{' \
    '  "nodes": {' \
    "    \"$name\": {\"locked\": {\"type\": \"github\", \"owner\": \"$owner\", \"repo\": \"$upstream\", \"rev\": \"$rev\"}}," \
    '    "root": {"inputs": {}}' \
    '  },' \
    '  "root": "root",' \
    '  "version": 7' \
    '}' > "$repo/flake.lock"
}

write_dual_lock() {
  local repo="$1" public_rev="$2" private_rev="$3"
  printf '%s\n' \
    '{' \
    '  "nodes": {' \
    "    \"inspr-modules\": {\"locked\": {\"type\": \"github\", \"owner\": \"inspr-at\", \"repo\": \"inspr-modules\", \"rev\": \"$public_rev\"}}," \
    "    \"inspr-doctrine-private\": {\"locked\": {\"type\": \"github\", \"owner\": \"inspr-at\", \"repo\": \"inspr-doctrine-private\", \"rev\": \"$private_rev\"}}," \
    '    "root": {"inputs": {}}' \
    '  },' \
    '  "root": "root",' \
    '  "version": 7' \
    '}' > "$repo/flake.lock"
}

run_check() {
  local repo="$1"
  shift
  (cd "$repo" && "$BASH_UNDER_TEST" "$CHECK" "$@") > "$last_output" 2>&1
  last_status=$?
}

expect_status() {
  local label="$1" expected="$2"
  if [[ "$last_status" -ne "$expected" ]]; then
    fail "$label: expected exit $expected, got $last_status"
    sed -n '1,120p' "$last_output" >&2
  fi
}

expect_output() {
  local label="$1" needle="$2"
  grep -Fq -- "$needle" "$last_output" || {
    fail "$label: missing output '$needle'"
    sed -n '1,120p' "$last_output" >&2
  }
}

reject_output() {
  local label="$1" needle="$2"
  if grep -Fq -- "$needle" "$last_output"; then
    fail "$label: focused mode unexpectedly ran '$needle'"
    sed -n '1,120p' "$last_output" >&2
  fi
}

# Same upstream, different revisions: fail with both activation directions.
# The gitlink has no checkout directory, proving index-only discovery.
repo=$(new_repo mismatch)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
printf '@./missing-doctrine-file.md\n' > "$repo/CLAUDE.md"
mkdir -p "$repo/.claude/commands"
printf 'copied command\n' > "$repo/.claude/commands/copied.md"
run_check "$repo" --multipath-only
expect_status "same-upstream mismatch" 1
expect_output "same-upstream mismatch" "consumption paths DISAGREE for inspr-at/inspr-modules"
expect_output "same-upstream mismatch" "submodule ahead => agents follow rules hosts do not implement"
expect_output "same-upstream mismatch" "flake input ahead => hosts run capabilities agents have not read"
reject_output "same-upstream mismatch" "@-ref does not resolve"
reject_output "same-upstream mismatch" "command is a COPY"
reject_output "same-upstream mismatch" "cannot reach origin"

# Consumer CI may initialize only public doctrine to obtain this checker. An
# absent doctrine-private checkout must not hide a private gitlink/flake split.
repo=$(new_repo uninitialized-private)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
add_gitlink "$repo" doctrine-private https://github.com/inspr-at/inspr-doctrine-private.git "$REV_A"
write_dual_lock "$repo" "$REV_A" "$REV_B"
[[ ! -e "$repo/doctrine-private" ]] || fail "private checkout fixture unexpectedly exists"
run_check "$repo" --multipath-only
expect_status "uninitialized private mismatch" 1
expect_output "uninitialized private mismatch" "consumption paths DISAGREE for inspr-at/inspr-doctrine-private"
expect_output "uninitialized private mismatch" "submodule doctrine-private"
expect_output "uninitialized private mismatch" "flake input inspr-doctrine-private"

# Two distinct doctrine upstreams are independent and therefore pass.
repo=$(new_repo distinct)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
add_gitlink "$repo" doctrine-private https://github.com/inspr-at/inspr-doctrine-private.git "$REV_B"
run_check "$repo" --multipath-only
expect_status "distinct upstreams" 0
expect_output "distinct upstreams" "2 consumption path(s), all agreeing per upstream"

# A repository with one applicable path has nothing to compare and passes.
repo=$(new_repo single)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
run_check "$repo" --multipath-only
expect_status "single path" 0
expect_output "single path" "single doctrine consumption path"

# The staged gitlink is authoritative even while HEAD still names the old pin.
repo=$(new_repo staged)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_A"
git -C "$repo" add flake.lock
git -C "$repo" commit -q -m "fixture: old doctrine pin"
git -C "$repo" update-index --cacheinfo 160000 "$REV_B" doctrine
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
git -C "$repo" add flake.lock
head_pin=$(git -C "$repo" ls-tree HEAD doctrine | awk '{print $3}')
index_pin=$(git -C "$repo" ls-files --stage doctrine | awk '{print $2}')
[[ "$head_pin" == "$REV_A" ]] || fail "staged fixture: HEAD does not retain old pin"
[[ "$index_pin" == "$REV_B" ]] || fail "staged fixture: index does not carry new pin"
run_check "$repo" --multipath-only
expect_status "staged gitlink" 0
expect_output "staged gitlink" "2 consumption path(s), all agreeing per upstream"

# The focused gate ignores assertions 1-4. The unchanged full gate still fails,
# while its existing --warn adoption mode still reports advisory and exits 0.
repo=$(new_repo mode-boundary)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_A"
printf '@./missing-doctrine-file.md\n' > "$repo/CLAUDE.md"
mkdir -p "$repo/.claude/commands"
printf 'copied command\n' > "$repo/.claude/commands/copied.md"
run_check "$repo" --multipath-only
expect_status "focused assertion boundary" 0
reject_output "focused assertion boundary" "@-ref does not resolve"
reject_output "focused assertion boundary" "command is a COPY"
reject_output "focused assertion boundary" "pin current"
reject_output "focused assertion boundary" "declared command list"
run_check "$repo"
expect_status "default semantics" 1
expect_output "default semantics" "@-ref does not resolve"
expect_output "default semantics" "command is a COPY"
run_check "$repo" --warn
expect_status "warn semantics" 0
expect_output "warn semantics" "issues above (advisory)"

# Discovery failures and invalid mode combinations fail closed.
repo=$(new_repo malformed-lock)
printf '{not json\n' > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "malformed flake.lock" 1
expect_output "malformed flake.lock" "flake.lock cannot be parsed"

repo=$(new_repo missing-url)
git -C "$repo" update-index --add --cacheinfo 160000 "$REV_A" doctrine
run_check "$repo" --multipath-only
expect_status "missing gitlink URL" 1
expect_output "missing gitlink URL" "indexed gitlink without a .gitmodules URL"

run_check "$repo" --unknown
expect_status "unknown argument" 2
expect_output "unknown argument" "usage: doctrine-check.sh"
run_check "$repo" --warn --multipath-only
expect_status "conflicting arguments" 2
expect_output "conflicting arguments" "usage: doctrine-check.sh"
run_check "$repo" --multipath-only --warn
expect_status "reversed conflicting arguments" 2

if [[ $failed -ne 0 ]]; then
  printf 'doctrine-check multipath tests: %d failure(s)\n' "$failed" >&2
  exit 1
fi

printf 'doctrine-check multipath tests: all assertions passed\n'
