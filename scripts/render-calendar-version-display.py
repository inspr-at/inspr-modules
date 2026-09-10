#!/usr/bin/env python3
"""Render the calendar v2 display data as CSS (INSPR-400).

Usage: render-calendar-version-display.py [--format css|json-flat] [path/to/calendar-version-display.json]

The JSON file is the single normative source for the weights, the tint and the
display design revision; no weight table is duplicated anywhere else in this
repository's production surfaces. This renderer is deterministic so consumers
and the doctrine's reference block can be compared byte for byte.
"""
import json
import pathlib
import sys

SEGMENTS = ["v", "yy", "mm", "dd", "hh", "mi", "ss", "tail"]


def load(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    validate(data)
    return data


def validate(data):
    if data.get("schema") != "inspr.calendar-version-display.v1":
        raise SystemExit("unsupported schema: %r" % data.get("schema"))
    if data.get("scheme") != "inspr-calendar-v2":
        raise SystemExit("display weights apply to inspr-calendar-v2 only")
    revision = data.get("design_revision")
    if not isinstance(revision, int) or isinstance(revision, bool) or revision < 1:
        raise SystemExit("design_revision must be a positive integer")
    if data.get("segments") != SEGMENTS:
        raise SystemExit("segments must be exactly %r" % SEGMENTS)
    weights = data["weights"]
    for seg in SEGMENTS:
        value = weights.get(seg)
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            raise SystemExit("weight %s must be a number" % seg)
        if not 0 <= value <= 1:
            raise SystemExit("weight %s must be within 0..1" % seg)
    for seg, minimum in data.get("floor", {}).items():
        if weights[seg] < minimum:
            raise SystemExit("weight %s below floor %s" % (seg, minimum))
    if weights["yy"] != 1:
        raise SystemExit("YY must keep full weight")
    tint = data["tint"]
    if not 0 <= tint["mix"] <= 1:
        raise SystemExit("tint mix must be within 0..1")
    unknown = set(tint["segments"]) - set(SEGMENTS)
    if unknown:
        raise SystemExit("unknown tint segments: %s" % sorted(unknown))
    default = tint.get("default")
    if not isinstance(default, str) or not default.strip():
        raise SystemExit("tint default must be a non-empty colour value")
    # The default lands verbatim in a CSS declaration; keep it a single value.
    if any(ch in default for ch in ";{}/\\\"'"):
        raise SystemExit("tint default must be a bare CSS colour value")
    if not isinstance(tint.get("space"), str) or not tint["space"].strip():
        raise SystemExit("tint space must be a non-empty colour space")
    props = data["css"]["properties"]
    for key in SEGMENTS + ["tint", "mix"]:
        if key not in props:
            raise SystemExit("css property mapping missing %s" % key)


def num(value):
    text = ("%.3f" % value).rstrip("0").rstrip(".")
    if text.startswith("0."):
        text = text[1:]
    return text or "0"


def render_css(data):
    weights = data["weights"]
    props = data["css"]["properties"]
    cls = data["css"]["class"]
    tint = data["tint"]
    typo = data["typography"]
    lines = []
    lines.append(
        "/* inspr-calendar-v2 display, design revision %d "
        "— generated from lib/calendar-version-display.json, do not edit by hand */"
        % data["design_revision"]
    )
    root = ";".join("%s:%s" % (props[seg], num(weights[seg])) for seg in SEGMENTS)
    lines.append(":root{%s;" % root)
    lines.append(
        "      %s:%s;%s:%s%%}   /* %s is the shared default Schmuckfarbe; a project MAY override it */"
        % (props["tint"], tint["default"], props["mix"], int(round(tint["mix"] * 100)), props["tint"])
    )
    lines.append(
        ".%s{font-family:%s;font-variant-numeric:%s;white-space:nowrap}"
        % (cls, typo["family"], typo["numeric"])
    )
    lines.append(".%s>b{font-weight:inherit}" % cls)
    rows = [
        ".%s .%s{opacity:var(%s)}" % (cls, seg, props[seg]) for seg in SEGMENTS
    ]
    for i in range(0, len(rows), 3):
        lines.append(" ".join(rows[i : i + 3]))
    selector = ",".join(".%s .%s" % (cls, seg) for seg in tint["segments"])
    lines.append(
        "%s{color:color-mix(in %s,currentColor,var(%s) var(%s))}"
        % (selector, tint["space"], props["tint"], props["mix"])
    )
    return "\n".join(lines) + "\n"


def render_flat(data):
    flat = {seg: data["weights"][seg] for seg in SEGMENTS}
    flat["design_revision"] = data["design_revision"]
    flat["tint_segments"] = data["tint"]["segments"]
    flat["tint_mix"] = data["tint"]["mix"]
    flat["tint_default"] = data["tint"]["default"]
    return json.dumps(flat, indent=2, sort_keys=True) + "\n"


def main(argv):
    fmt = "css"
    args = list(argv)
    if args and args[0] == "--format":
        fmt = args[1]
        args = args[2:]
    default = pathlib.Path(__file__).resolve().parent.parent / "lib" / "calendar-version-display.json"
    path = pathlib.Path(args[0]) if args else default
    data = load(path)
    if fmt == "css":
        sys.stdout.write(render_css(data))
    elif fmt == "json-flat":
        sys.stdout.write(render_flat(data))
    else:
        raise SystemExit("unknown format: %s" % fmt)


if __name__ == "__main__":
    main(sys.argv[1:])
