#!/usr/bin/env bash
# Offline guard contract tests; no repository index or Git objects are changed.
set -euo pipefail
repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
python3 - "$repo_root" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap

root = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix="leak-guard-test-") as directory:
    fixture = Path(directory)
    (fixture / "bin").mkdir()
    (fixture / "scripts").mkdir()
    shutil.copyfile(root / "scripts/leak-guard.sh", fixture / "scripts/leak-guard.sh")
    # Stub only Git's read-only discovery: exercise the real scanner and files.
    git = fixture / "bin/git"
    # Absolute interpreter path: the Nix build sandbox has no /usr/bin/env.
    git.write_text("#!" + shutil.which("bash") + '''
case "$*" in
  "rev-parse --is-inside-work-tree") exit "${GIT_STATUS:-0}";;
  "rev-parse --show-prefix") printf '%s' "${GIT_PREFIX:-}";;
  "ls-files") printf '%s' "${SCAN_FILES:-}";;
  *) exit 2;;
esac
''')
    git.chmod(0o755)
    base = os.environ.copy()
    for key in ("LEAK_GUARD_PATTERNS", "LEAK_GUARD_PATTERNS_FILE"):
        base.pop(key, None)
    base.update(PATH=str(fixture / "bin") + os.pathsep + base["PATH"], SCAN_FILES="sample.txt")
    sample = fixture / "sample.txt"
    sample.write_text("synthetic-sensitive-marker\n")
    checks = 0

    def check(label, expected, settings=None, script=None, notice=None):
        global checks
        result = subprocess.run(
            ["bash", "-c", script] if script else ["bash", "scripts/leak-guard.sh"],
            cwd=fixture, env={**base, **(settings or {})}, capture_output=True, text=True)
        output = result.stdout + result.stderr
        assert result.returncode == expected, (label, result.returncode, output)
        assert "synthetic-sensitive-marker" not in output, (label, "unredacted pattern/content")
        if notice:
            assert notice in output, (label, output)
        checks += 1

    check("generic-only", 0)
    check("environment pattern", 1, {"LEAK_GUARD_PATTERNS": "synthetic-sensitive-marker"})
    pattern_file = fixture / "patterns.txt"
    pattern_file.write_text("\n  # comment\n\nsynthetic-sensitive-marker\n")
    check("file pattern", 1, {"LEAK_GUARD_PATTERNS_FILE": str(pattern_file)})
    pattern_file.write_text("^unrelated$\n")
    check("sources are additive", 1, {"LEAK_GUARD_PATTERNS_FILE": str(pattern_file),
                                     "LEAK_GUARD_PATTERNS": "synthetic-sensitive-marker"})
    pattern_file.write_text("synthetic-sensitive-marker\n")
    check("file still used with env", 1, {"LEAK_GUARD_PATTERNS_FILE": str(pattern_file),
                                         "LEAK_GUARD_PATTERNS": "^unrelated$"})
    check("comments and blanks", 0, {"LEAK_GUARD_PATTERNS": "\n # comment\n\t\n"})
    check("unreadable source", 2, {"LEAK_GUARD_PATTERNS_FILE": str(fixture / "missing")},
          notice="unreadable")
    pattern_file.chmod(0)
    if not os.access(pattern_file, os.R_OK):
        check("denied source", 2, {"LEAK_GUARD_PATTERNS_FILE": str(pattern_file)})
    pattern_file.chmod(0o600)
    check("invalid env regex", 2, {"LEAK_GUARD_PATTERNS": "["})
    pattern_file.write_text("[\n")
    check("invalid file regex", 2, {"LEAK_GUARD_PATTERNS_FILE": str(pattern_file)})
    check("outside git", 2, {"GIT_STATUS": "1"})
    check("non-root invocation", 2, {"GIT_PREFIX": "subdir/"})
    check("empty tracked set", 2, {"SCAN_FILES": ""})
    check("excluded-only set", 2, {"SCAN_FILES": "scripts/leak-guard.sh"})
    check("unreadable tracked file", 2, {"SCAN_FILES": "missing.txt"})
    sample.write_bytes(b"\x00synthetic-sensitive-marker\x00\n")
    check("binary redaction", 1, {"LEAK_GUARD_PATTERNS": "synthetic-sensitive-marker"})
    sample.write_text("api" + "_key=" + "synthetic" * 4 + "\n")
    check("generic credential shape", 1)
    sample.write_text("clean fixture\n")

    # Execute the workflow's real shell body in trusted and fork contexts.
    workflow = (root / ".github/workflows/leak-guard.yml").read_text()
    assert "LEAK_GUARD_PATTERNS: ${{ secrets.LEAK_GUARD_PATTERNS }}" in workflow
    assert "github.event_name == 'push'" in workflow
    assert "github.event.pull_request.head.repo.full_name == github.repository" in workflow
    body = textwrap.dedent(workflow.split("        run: |\n", 1)[1])
    check("trusted missing secret", 1, {"TRUSTED_RUN": "true"}, body,
          "requires the LEAK_GUARD_PATTERNS repository secret")
    check("trusted supplied secret", 0, {"TRUSTED_RUN": "true",
          "LEAK_GUARD_PATTERNS": "^unrelated$"}, body)
    check("fork generic-only", 0, {"TRUSTED_RUN": "false"}, body, "running generic-only")
    print(f"leak-guard pattern sources and CI branches: {checks} checks passed")
PY
