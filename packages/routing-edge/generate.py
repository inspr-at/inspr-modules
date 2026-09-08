#!/usr/bin/env python3
"""Generate Traefik 3.7.12 file-provider configuration from an INSPR routing contract."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(PACKAGE_ROOT))

from routing_edge.compile import compile_edge, write_outputs  # noqa: E402


def main(arguments: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--deployment", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(arguments)

    try:
        contract = json.loads(args.contract.read_text(encoding="utf-8"))
        deployment = json.loads(args.deployment.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"MALFORMED_DOCUMENT: {error}", file=sys.stderr)
        return 2

    result = compile_edge(contract, deployment)
    if not result.ok:
        for finding in result.findings:
            print(finding, file=sys.stderr)
        return 1
    write_outputs(result, args.output_dir)
    print(f"{args.output_dir / 'dynamic.yml'}: generated")
    if result.static:
        print(f"{args.output_dir / 'static.yml'}: generated")
    print(f"{args.output_dir / 'wiring-report.json'}: generated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
