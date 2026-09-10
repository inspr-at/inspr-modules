#!/usr/bin/env bash
# The calendar v2 display weights are data (INSPR-400): lib/calendar-version-display.json
# is normative, the doctrine's CSS block and prose numbers are rendered from it.
set -euo pipefail
repo_root=${1:?repository root is required}
fail() {
  printf 'calendar-version-display: %s\n' "$*" >&2
  exit 1
}
data="$repo_root/lib/calendar-version-display.json"
policy="$repo_root/docs/AGENTS-VERSIONING.md"
renderer="$repo_root/scripts/render-calendar-version-display.py"
skill="$repo_root/skills/inspr-worker-doctrine/SKILL.md"
test -f "$data" || fail 'lib/calendar-version-display.json is missing'
test -f "$renderer" || fail 'renderer is missing'
grep -Fq 'lib/calendar-version-display.json' "$policy" \
  || fail 'doctrine does not name the data file as normative source'
grep -Fq 'references/calendar-version-display.json' "$skill" \
  || fail 'worker skill does not link the display-weights data'
python3 - "$data" "$policy" "$renderer" <<'PY'
import json, pathlib, re, subprocess, sys
data_path, policy_path, renderer = sys.argv[1:4]
data = json.loads(pathlib.Path(data_path).read_text())
rendered = subprocess.run([sys.executable, renderer, data_path], capture_output=True, text=True, check=True).stdout
policy = pathlib.Path(policy_path).read_text()
m = re.search(r"Reference implementation for the web.*?```css\n(.*?)```\n", policy, re.S)
if not m:
    sys.exit("calendar-version-display: doctrine CSS block not found")
if m.group(1) != rendered:
    sys.exit("calendar-version-display: doctrine CSS block differs from rendered data; regenerate with scripts/render-calendar-version-display.py")
labels = {"v": "v", "yy": "YY", "mm": "MM", "dd": "DD", "hh": "hh", "mi": "mm", "ss": "ss", "tail": ".0.0"}
prose = ", ".join("`%s` %d" % (labels[s], round(data["weights"][s] * 100)) for s in data["segments"])
flat = re.sub(r"\s+", " ", policy)
if prose not in flat:
    sys.exit("calendar-version-display: prose default weights differ from data: expected '%s'" % prose)
mix = "%d percent colour mix" % round(data["tint"]["mix"] * 100)
if mix not in flat:
    sys.exit("calendar-version-display: prose tint mix differs from data: expected '%s'" % mix)
print("calendar-version-display: ok")
PY
