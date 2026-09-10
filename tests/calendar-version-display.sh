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
import json, os, pathlib, re, subprocess, sys, tempfile
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

# Approved display design revision 3 (INSPR-414), screenshot-approved by the
# operator. This literal table exists only here, as the regression anchor for
# the approved settings; every production surface reads the JSON instead.
APPROVED_REVISION = 3
APPROVED_WEIGHTS = {
    "v": 0.2, "yy": 1.0, "mm": 0.8, "dd": 1.0,
    "hh": 0.6, "mi": 0.4, "ss": 0.2, "tail": 0.2,
}
APPROVED_TINT = {
    "segments": ["yy", "mm", "dd"],
    "mix": 0.8,
    "space": "oklab",
    "default": "#d69b31",
}
if data.get("design_revision") != APPROVED_REVISION:
    sys.exit("calendar-version-display: design_revision is %r, approved is %r"
             % (data.get("design_revision"), APPROVED_REVISION))
for seg, expected in APPROVED_WEIGHTS.items():
    if float(data["weights"][seg]) != expected:
        sys.exit("calendar-version-display: weight %s is %r, approved is %r"
                 % (seg, data["weights"][seg], expected))
for key, expected in APPROVED_TINT.items():
    if data["tint"][key] != expected:
        sys.exit("calendar-version-display: tint %s is %r, approved is %r"
                 % (key, data["tint"][key], expected))

# A design revision is presentation only: the scheme and the data schema stay
# put, so no consumer has to treat it as a grammar migration.
if data["schema"] != "inspr.calendar-version-display.v1":
    sys.exit("calendar-version-display: data schema changed; a design revision must stay schema-compatible")
if data["scheme"] != "inspr-calendar-v2":
    sys.exit("calendar-version-display: scheme changed; a design revision is not a version scheme migration")

# The revision is explicit in the generated CSS and in the doctrine prose, so a
# consumer can tell which revision it has pinned without diffing numbers.
if "design revision %d" % APPROVED_REVISION not in rendered:
    sys.exit("calendar-version-display: rendered CSS does not name the design revision")
if "display design revision %d" % APPROVED_REVISION not in flat:
    sys.exit("calendar-version-display: doctrine prose does not name the current design revision")
if data["tint"]["default"] not in flat:
    sys.exit("calendar-version-display: doctrine prose does not name the default tint colour")

# Weighting never touches the string: the reference markup's text content is
# still exactly the canonical coordinate, separators and all.
html = re.search(r"```html\n(.*?)```", policy, re.S)
if not html:
    sys.exit("calendar-version-display: doctrine HTML example not found")
text = re.sub(r"<[^>]+>", "", html.group(1)).strip()
if text != "v260909202506.0.0":
    sys.exit("calendar-version-display: reference markup no longer renders the plain canonical string: %r" % text)

# Invalid shapes must fail loudly rather than render something plausible.
def rejects(mutate, label):
    broken = json.loads(json.dumps(data))
    mutate(broken)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(broken, fh)
        path = fh.name
    try:
        proc = subprocess.run([sys.executable, renderer, path], capture_output=True, text=True)
    finally:
        os.unlink(path)
    if proc.returncode == 0:
        sys.exit("calendar-version-display: renderer accepted an invalid shape: %s" % label)

rejects(lambda d: d.pop("design_revision"), "missing design_revision")
rejects(lambda d: d.update(design_revision=0), "non-positive design_revision")
rejects(lambda d: d.update(design_revision="3"), "non-integer design_revision")
rejects(lambda d: d.update(scheme="inspr-calendar-v3"), "foreign scheme")
rejects(lambda d: d["weights"].update(yy=0.9), "YY below its floor")
rejects(lambda d: d["weights"].update(dd=1.5), "weight outside 0..1")
rejects(lambda d: d["tint"].update(mix=1.5), "tint mix outside 0..1")
rejects(lambda d: d["tint"].update(default=""), "empty tint default")
rejects(lambda d: d["tint"].update(default="red;color:blue"), "tint default carrying a second declaration")
rejects(lambda d: d["tint"].update(segments=["yy", "zz"]), "unknown tint segment")

print("calendar-version-display: ok")
PY
