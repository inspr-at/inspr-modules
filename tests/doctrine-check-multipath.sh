#!/usr/bin/env bash
# Focused doctrine-check contract (INSPR-323).
set -uo pipefail

SOURCE_ROOT="${1:?usage: doctrine-check-multipath.sh SOURCE_ROOT}"
CHECK="$SOURCE_ROOT/scripts/doctrine-check.sh"
BASH_UNDER_TEST="${DOCTRINE_TEST_BASH:-/bin/bash}"
REV_A="1111111111111111111111111111111111111111"
REV_B="2222222222222222222222222222222222222222"
REV_C="3333333333333333333333333333333333333333"
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

# Nix checks run with a current Bash even on macOS, so executing the fixture
# there cannot by itself enforce the public Bash 3.2 compatibility promise.
# Keep a small fail-closed syntax surface for constructs introduced after 3.2;
# the full suite still executes under the host /bin/bash during local macOS QA.
bash32_syntax_compatible() {
  local path="$1"
  ! grep -Ev '^[[:space:]]*#' "$path" | grep -Eq \
    '(^|[[:space:];])(declare[[:space:]]+-A|readarray|mapfile|coproc)([[:space:];]|$)|&>>|\$\{[^}]*\^\^|\$\{[^}]*,,|\$\{[^}]*@[A-Za-z]\}|\[\[[[:space:]]+-v[[:space:]]|(^|[[:space:];])wait[[:space:]]+-n([[:space:];]|$)'
}

if ! bash32_syntax_compatible "$CHECK"; then
  fail "doctrine-check uses syntax newer than macOS Bash 3.2"
fi
bash4_probe="$TMP_ROOT/bash4-only.sh"
printf '%s\n' 'declare -A bash4_only=([x]=1)' > "$bash4_probe"
if bash32_syntax_compatible "$bash4_probe"; then
  fail "Bash 3.2 syntax guard did not reject an associative array"
fi

new_repo() {
  local name="$1" path="$TMP_ROOT/$1"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name "Doctrine Check Fixture"
  git -C "$path" config user.email "fixture@example.invalid"
  printf '%s\n' "$path"
}

add_gitlink_named() {
  local repo="$1" section="$2" path="$3" url="$4" rev="$5"
  printf '[submodule "%s"]\n\tpath = %s\n\turl = %s\n' \
    "$section" "$path" "$url" >> "$repo/.gitmodules"
  git -C "$repo" update-index --add --cacheinfo 160000 "$rev" "$path"
  git -C "$repo" add .gitmodules
}

add_gitlink() {
  add_gitlink_named "$1" "$2" "$2" "$3" "$4"
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

write_git_lock() {
  local repo="$1" name="$2" url="$3" rev="$4"
  printf '%s\n' \
    '{' \
    '  "nodes": {' \
    "    \"$name\": {\"locked\": {\"type\": \"git\", \"url\": \"$url\", \"rev\": \"$rev\"}}," \
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

run_check_with_upstreams() {
  local repo="$1" upstreams="$2"
  shift 2
  (cd "$repo" && DOCTRINE_UPSTREAMS="$upstreams" "$BASH_UNDER_TEST" "$CHECK" "$@") \
    > "$last_output" 2>&1
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

# Standard GitHub URL forms identify the same upstream as a locked GitHub
# owner/repo node. Scheme spelling must not turn a mismatch into two paths.
repo=$(new_repo ssh-url-identity)
add_gitlink "$repo" doctrine ssh://git@github.com/inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "SSH URL identity" 1
expect_output "SSH URL identity" "consumption paths DISAGREE for inspr-at/inspr-modules"

repo=$(new_repo scp-url-identity)
add_gitlink "$repo" doctrine git@github.com:inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "SCP URL identity" 1
expect_output "SCP URL identity" "consumption paths DISAGREE for inspr-at/inspr-modules"

# A non-GitHub host remains part of repository identity. Sharing owner/repo
# text with GitHub must not collapse GitLab and GitHub into one upstream.
repo=$(new_repo distinct-git-host)
add_gitlink "$repo" doctrine ssh://git@gitlab.com/inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "distinct Git host" 0
expect_output "distinct Git host" "2 consumption path(s), all agreeing per upstream"

# Outside the proven GitHub forms, transport authority and path spelling remain
# identity-significant. Collapsing any of these pairs creates a false split.
repo=$(new_repo distinct-ssh-ports)
add_gitlink "$repo" doctrine ssh://git@example.com:2222/inspr-at/inspr-modules.git "$REV_A"
write_git_lock "$repo" doctrine-port ssh://git@example.com:3333/inspr-at/inspr-modules.git "$REV_B"
run_check "$repo" --multipath-only
expect_status "distinct SSH ports" 0
expect_output "distinct SSH ports" "2 consumption path(s), all agreeing per upstream"

repo=$(new_repo distinct-ssh-users)
add_gitlink "$repo" doctrine ssh://alice@example.com/inspr-at/inspr-modules.git "$REV_A"
write_git_lock "$repo" doctrine-user ssh://bob@example.com/inspr-at/inspr-modules.git "$REV_B"
run_check "$repo" --multipath-only
expect_status "distinct SSH users" 0
expect_output "distinct SSH users" "2 consumption path(s), all agreeing per upstream"

repo=$(new_repo distinct-path-case)
add_gitlink "$repo" doctrine ssh://git@example.com/INSPR-AT/inspr-modules.git "$REV_A"
write_git_lock "$repo" doctrine-case ssh://git@example.com/inspr-at/inspr-modules.git "$REV_B"
run_check "$repo" --multipath-only
expect_status "distinct path case" 0
expect_output "distinct path case" "2 consumption path(s), all agreeing per upstream"

# Git resolves ../ submodule URLs relative to the superproject's remote URL.
repo=$(new_repo relative-submodule-url)
git -C "$repo" remote add origin https://github.com/inspr-at/consumer.git
add_gitlink "$repo" doctrine ../inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "relative submodule URL" 1
expect_output "relative submodule URL" "consumption paths DISAGREE for inspr-at/inspr-modules"

# Git resolves a relative submodule URL against the current branch's tracking
# remote. `origin` is only the fallback when no tracking remote is configured.
repo=$(new_repo tracking-default-remote)
git -C "$repo" symbolic-ref HEAD refs/heads/main
git -C "$repo" remote add origin https://gitlab.com/inspr-at/consumer.git
git -C "$repo" remote add upstream https://github.com/inspr-at/consumer.git
git -C "$repo" config branch.main.remote upstream
git -C "$repo" config branch.main.merge refs/heads/main
add_gitlink "$repo" doctrine ../inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "tracking default remote" 1
expect_output "tracking default remote" "consumption paths DISAGREE for inspr-at/inspr-modules"

repo=$(new_repo relative-without-origin)
add_gitlink "$repo" doctrine ../inspr-modules.git "$REV_A"
run_check "$repo" --multipath-only
expect_status "relative URL without origin" 1
expect_output "relative URL without origin" "relative URL but no usable default Git remote exists"

# Git URL rewriting is repository-local identity resolution and does not need
# network access. It applies to both submodule URLs and locked.type=git URLs.
repo=$(new_repo submodule-insteadof)
git -C "$repo" config url.git@github.com:.insteadOf git@git-personal:
add_gitlink "$repo" doctrine git@git-personal:inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "submodule insteadOf" 1
expect_output "submodule insteadOf" "consumption paths DISAGREE for inspr-at/inspr-modules"

repo=$(new_repo flake-git-insteadof)
git -C "$repo" config url.git@github.com:.insteadOf git@git-personal:
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
write_git_lock "$repo" doctrine-git git@git-personal:inspr-at/inspr-modules.git "$REV_B"
run_check "$repo" --multipath-only
expect_status "flake git insteadOf" 1
expect_output "flake git insteadOf" "consumption paths DISAGREE for inspr-at/inspr-modules"

repo=$(new_repo ambiguous-effective-url)
git -C "$repo" remote add doctrine-source https://github.com/inspr-at/inspr-modules.git
git -C "$repo" config --add remote.doctrine-source.url https://gitlab.com/inspr-at/inspr-modules.git
add_gitlink "$repo" doctrine doctrine-source "$REV_A"
run_check "$repo" --multipath-only
expect_status "ambiguous effective Git URL" 1
expect_output "ambiguous effective Git URL" "does not resolve to exactly one effective Git URL"

# A local path is not GitHub merely because its last two components look like
# owner/repo. Use a real bare repository for the plain relative-path case.
repo=$(new_repo local-git-path)
mkdir -p "$repo/inspr-at"
git -C "$repo/inspr-at" init -q --bare inspr-modules.git
add_gitlink "$repo" doctrine inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "real local Git path" 1
expect_output "real local Git path" ".gitmodules URL cannot be normalized to one upstream identity"
reject_output "real local Git path" "consumption paths DISAGREE for inspr-at/inspr-modules"

repo=$(new_repo absolute-local-shape)
add_gitlink "$repo" doctrine /inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "absolute local Git path" 1
expect_output "absolute local Git path" ".gitmodules URL cannot be normalized to one upstream identity"
reject_output "absolute local Git path" "consumption paths DISAGREE for inspr-at/inspr-modules"

repo=$(new_repo flake-local-path)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
write_git_lock "$repo" doctrine-local inspr-at/inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "flake local Git path" 1
expect_output "flake local Git path" "flake node cannot be normalized to one upstream identity"
reject_output "flake local Git path" "consumption paths DISAGREE for inspr-at/inspr-modules"

# `.gitmodules` section names are caller-selected; path, not section spelling,
# binds the indexed gitlink to its URL.
repo=$(new_repo custom-section)
add_gitlink_named "$repo" vendor-doctrine doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "custom submodule section" 1
expect_output "custom submodule section" "consumption paths DISAGREE for inspr-at/inspr-modules"

repo=$(new_repo spaced-section)
add_gitlink_named "$repo" "vendor doctrine" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "spaced submodule section" 1
expect_output "spaced submodule section" "consumption paths DISAGREE for inspr-at/inspr-modules"

# A valid Nix locked.type=git node participates using the same URL identity.
repo=$(new_repo locked-git)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
write_git_lock "$repo" doctrine-git git://github.com/inspr-at/inspr-modules.git "$REV_B"
run_check "$repo" --multipath-only
expect_status "locked git input" 1
expect_output "locked git input" "consumption paths DISAGREE for inspr-at/inspr-modules"

# Doctrine-relevant lock nodes cannot disappear merely because a required
# identity or revision field is absent. Unrelated malformed nodes stay outside
# this focused check's ownership.
repo=$(new_repo relevant-missing-rev)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
printf '%s\n' \
  '{"nodes":{"inspr-modules":{"locked":{"type":"github","owner":"inspr-at","repo":"inspr-modules"}}},"root":"root","version":7}' \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "relevant lock missing rev" 1
expect_output "relevant lock missing rev" "doctrine-relevant flake node is malformed"

repo=$(new_repo relevant-missing-identity)
printf '%s\n' \
  "{\"nodes\":{\"inspr-modules\":{\"locked\":{\"type\":\"github\",\"repo\":\"inspr-modules\",\"rev\":\"$REV_A\"}}},\"root\":\"root\",\"version\":7}" \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "relevant lock missing identity" 1
expect_output "relevant lock missing identity" "doctrine-relevant flake node is malformed"

repo=$(new_repo relevant-git-missing-rev)
printf '%s\n' \
  '{"nodes":{"doctrine-git":{"locked":{"type":"git","url":"https://github.com/inspr-at/inspr-modules.git"}}},"root":"root","version":7}' \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "relevant git lock missing rev" 1
expect_output "relevant git lock missing rev" "doctrine-relevant flake node is malformed"

repo=$(new_repo unrelated-malformed-lock)
printf '%s\n' \
  '{"nodes":{"unrelated":{"locked":{"type":"github","owner":"example","repo":"other"}}},"root":"root","version":7}' \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "unrelated malformed lock" 0
expect_output "unrelated malformed lock" "single doctrine consumption path"

# Relevance can come from a flake input edge even when the locked node ID is
# opaque and none of its malformed fields name doctrine.
repo=$(new_repo opaque-relevant-edge)
printf '%s\n' \
  '{"nodes":{"root":{"inputs":{"inspr-modules":"opaque"}},"opaque":{"locked":null}},"root":"root","version":7}' \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "opaque relevant input edge" 1
expect_output "opaque relevant input edge" "doctrine-relevant flake node is malformed"

# A follows path is itself an input reference. Relevance in any component must
# make an unresolvable path fail even when the outer alias is neutral.
repo=$(new_repo relevant-follows-component)
printf '%s\n' \
  '{"nodes":{"root":{"inputs":{"policy":["opaque","inspr-modules"]}}},"root":"root","version":7}' \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "relevant follows component" 1
expect_output "relevant follows component" "doctrine-relevant flake node is malformed"

# `original` identifies the requested upstream even when the locked node ID and
# locked fields do not. Null or cross-upstream locks must not disappear.
repo=$(new_repo original-relevant-null-lock)
printf '%s\n' \
  '{"nodes":{"opaque":{"original":{"type":"github","owner":"inspr-at","repo":"inspr-modules"},"locked":null}},"root":"opaque","version":7}' \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "original relevant null lock" 1
expect_output "original relevant null lock" "doctrine-relevant flake node is malformed"

repo=$(new_repo original-locked-inconsistent)
printf '%s\n' \
  "{\"nodes\":{\"opaque\":{\"original\":{\"type\":\"github\",\"owner\":\"inspr-at\",\"repo\":\"inspr-modules\"},\"locked\":{\"type\":\"github\",\"owner\":\"example\",\"repo\":\"other\",\"rev\":\"$REV_A\"}}},\"root\":\"opaque\",\"version\":7}" \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "original and locked inconsistent" 1
expect_output "original and locked inconsistent" "original and locked doctrine identities disagree"

repo=$(new_repo locked-relevant-original-elsewhere)
printf '%s\n' \
  "{\"nodes\":{\"opaque\":{\"original\":{\"type\":\"github\",\"owner\":\"example\",\"repo\":\"other\"},\"locked\":{\"type\":\"github\",\"owner\":\"inspr-at\",\"repo\":\"inspr-modules\",\"rev\":\"$REV_A\"}}},\"root\":\"opaque\",\"version\":7}" \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "locked relevant original elsewhere" 1
expect_output "locked relevant original elsewhere" "original and locked doctrine identities disagree"

repo=$(new_repo unrelated-original-null-lock)
printf '%s\n' \
  '{"nodes":{"opaque":{"original":{"type":"github","owner":"example","repo":"other"},"locked":null}},"root":"opaque","version":7}' \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "unrelated original null lock" 0
expect_output "unrelated original null lock" "single doctrine consumption path"

# A relevant follows path that resolves back to its owning node is a cycle,
# even when that node also has a superficially valid doctrine lock.
repo=$(new_repo relevant-self-follow)
printf '%s\n' \
  "{\"nodes\":{\"root\":{\"inputs\":{\"base\":\"base\"}},\"base\":{\"inputs\":{\"inspr-modules\":[\"base\"]},\"locked\":{\"type\":\"github\",\"owner\":\"inspr-at\",\"repo\":\"inspr-modules\",\"rev\":\"$REV_A\"}}},\"root\":\"root\",\"version\":7}" \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "relevant self-follow" 1
expect_output "relevant self-follow" "doctrine-relevant flake node is malformed"

# Relevant follows edges can also cycle across nodes. Equal locked revisions do
# not make that graph valid: discovery must reject A -> B -> A before comparing.
repo=$(new_repo relevant-multi-node-cycle)
printf '%s\n' \
  "{\"nodes\":{\"root\":{\"inputs\":{\"a\":\"a\",\"b\":\"b\"}},\"a\":{\"inputs\":{\"inspr-modules\":[\"b\"]},\"locked\":{\"type\":\"github\",\"owner\":\"inspr-at\",\"repo\":\"inspr-modules\",\"rev\":\"$REV_A\"}},\"b\":{\"inputs\":{\"inspr-modules\":[\"a\"]},\"locked\":{\"type\":\"github\",\"owner\":\"inspr-at\",\"repo\":\"inspr-modules\",\"rev\":\"$REV_A\"}}},\"root\":\"root\",\"version\":7}" \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "relevant multi-node cycle" 1
expect_output "relevant multi-node cycle" "doctrine-relevant flake node is malformed"

repo=$(new_repo valid-nested-follow)
printf '%s\n' \
  "{\"nodes\":{\"root\":{\"inputs\":{\"base\":\"base\",\"policy\":[\"base\",\"inspr-modules\"]}},\"base\":{\"inputs\":{\"inspr-modules\":\"target\"}},\"target\":{\"locked\":{\"type\":\"github\",\"owner\":\"inspr-at\",\"repo\":\"inspr-modules\",\"rev\":\"$REV_A\"}}},\"root\":\"root\",\"version\":7}" \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "valid nested follow" 0
expect_output "valid nested follow" "single doctrine consumption path"

# A follows path may traverse a doctrine node and terminate at an ordinary
# dependency. Only the terminal node's own identity decides whether it is a
# doctrine consumption path; the intermediate name must not taint nixpkgs.
repo=$(new_repo valid-follow-through-doctrine)
printf '%s\n' \
  "{\"nodes\":{\"root\":{\"inputs\":{\"inspr-modules\":\"inspr-modules\",\"inspr-doctrine-private\":\"inspr-doctrine-private\"}},\"inspr-modules\":{\"inputs\":{\"nixpkgs\":\"nixpkgs_2\"},\"locked\":{\"type\":\"github\",\"owner\":\"inspr-at\",\"repo\":\"inspr-modules\",\"rev\":\"$REV_A\"}},\"inspr-doctrine-private\":{\"inputs\":{\"nixpkgs\":[\"inspr-modules\",\"nixpkgs\"]},\"locked\":{\"type\":\"github\",\"owner\":\"inspr-at\",\"repo\":\"inspr-doctrine-private\",\"rev\":\"$REV_A\"}},\"nixpkgs_2\":{\"locked\":{\"type\":\"github\",\"owner\":\"NixOS\",\"repo\":\"nixpkgs\",\"rev\":\"$REV_B\"}}},\"root\":\"root\",\"version\":7}" \
  > "$repo/flake.lock"
run_check "$repo" --multipath-only
expect_status "valid follow through doctrine" 0
expect_output "valid follow through doctrine" "2 consumption path(s), all agreeing per upstream"

# An invalid configured relevance regex is a configuration error, not a clean
# repository. It must be diagnosed before any path filtering occurs.
repo=$(new_repo invalid-upstream-regex)
run_check_with_upstreams "$repo" '[' --multipath-only
expect_status "invalid doctrine regex" 2
expect_output "invalid doctrine regex" "DOCTRINE_UPSTREAMS is not a valid regular expression"

# An unresolved gitlink merge has stages 1/2/3 and no authoritative stage 0.
# Silently treating it as absent would leave the flake input as a vacuous
# single path exactly while a doctrine-pin merge is unresolved.
repo=$(new_repo unmerged-index)
add_gitlink "$repo" doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
git -C "$repo" update-index --force-remove doctrine
printf '160000 %s 1\tdoctrine\n160000 %s 2\tdoctrine\n160000 %s 3\tdoctrine\n' \
  "$REV_A" "$REV_B" "$REV_C" | git -C "$repo" update-index --index-info
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_B"
run_check "$repo" --multipath-only
expect_status "unresolved gitlink index" 1
expect_output "unresolved gitlink index" "doctrine index has 3 row(s)"
expect_output "unresolved gitlink index" "exactly one stage-0 gitlink"

# A Git-index read failure is not equivalent to an absent named path.
repo=$(new_repo unreadable-index)
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_A"
printf 'not a Git index\n' > "$repo/.git/index"
run_check "$repo" --multipath-only
expect_status "Git index read failure" 1
expect_output "Git index read failure" "cannot read Git index for doctrine"

repo=$(new_repo ambiguous-submodule-path)
add_gitlink_named "$repo" vendor-one doctrine https://github.com/inspr-at/inspr-modules.git "$REV_A"
printf '[submodule "vendor-two"]\n\tpath = doctrine\n\turl = https://github.com/inspr-at/inspr-modules.git\n' \
  >> "$repo/.gitmodules"
git -C "$repo" add .gitmodules
run_check "$repo" --multipath-only
expect_status "ambiguous submodule path" 1
expect_output "ambiguous submodule path" "doctrine has 2 matching .gitmodules path entries"

# No named path is a valid single-path repository. A named regular file is not
# absence: it is a malformed consumer path and must fail closed. The atelier's
# canonical `doctrine -> .` index symlink remains an explicit non-pin case.
repo=$(new_repo flake-only)
write_lock "$repo" inspr-modules inspr-at inspr-modules "$REV_A"
run_check "$repo" --multipath-only
expect_status "flake-only single path" 0
expect_output "flake-only single path" "single doctrine consumption path"

repo=$(new_repo malformed-named-path)
printf 'not a gitlink\n' > "$repo/doctrine"
git -C "$repo" add doctrine
run_check "$repo" --multipath-only
expect_status "malformed named path" 1
expect_output "malformed named path" "doctrine index has mode 100644 at stage 0"
expect_output "malformed named path" "exactly one stage-0 gitlink"

repo=$(new_repo atelier-self-link)
ln -s . "$repo/doctrine"
git -C "$repo" add doctrine
run_check "$repo" --multipath-only
expect_status "atelier self-symlink" 0
expect_output "atelier self-symlink" "indexed self-symlink -> ., not a pin"

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
expect_status "missing gitmodules path" 1
expect_output "missing gitmodules path" "doctrine has 0 matching .gitmodules path entries"

repo=$(new_repo matching-path-missing-url)
git -C "$repo" update-index --add --cacheinfo 160000 "$REV_A" doctrine
printf '[submodule "vendor-doctrine"]\n\tpath = doctrine\n' > "$repo/.gitmodules"
git -C "$repo" add .gitmodules
run_check "$repo" --multipath-only
expect_status "matching path missing URL" 1
expect_output "matching path missing URL" "doctrine .gitmodules section has 0 URL entries"

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
