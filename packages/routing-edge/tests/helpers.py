from __future__ import annotations

import copy
import json
import socket
import sys
from pathlib import Path
from typing import Any

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = PACKAGE_ROOT.parents[1]
sys.path.insert(0, str(PACKAGE_ROOT))
sys.path.insert(0, str(REPO_ROOT / "contracts" / "routing"))

from routing_edge.compile import compile_edge  # noqa: E402


CONTRACTS = REPO_ROOT / "contracts" / "routing" / "fixtures"
DEPLOYMENTS = PACKAGE_ROOT / "fixtures"


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def apply_pointer(document: Any, pointer: str, op: str, value: Any | None = None) -> None:
    parts = [part.replace("~1", "/").replace("~0", "~") for part in pointer.lstrip("/").split("/")]
    target = document
    for part in parts[:-1]:
        target = target[int(part)] if isinstance(target, list) else target[part]
    leaf = parts[-1]
    if op == "remove":
        if isinstance(target, list):
            del target[int(leaf)]
        else:
            del target[leaf]
        return
    if isinstance(target, list):
        target[int(leaf)] = value
    else:
        target[leaf] = value


def apply_fixture_patch(fixture_path: Path) -> tuple[dict[str, Any], set[str]]:
    fixture = load_json(fixture_path)
    document = copy.deepcopy(load_json((fixture_path.parent / fixture["base"]).resolve()))
    for operation in fixture["operations"]:
        apply_pointer(document, operation["path"], operation["op"], operation.get("value"))
    return document, set(fixture["expected_codes"])


def compile_named(contract_name: str, deployment_name: str):
    contract = load_json(CONTRACTS / "valid" / contract_name)
    deployment = load_json(DEPLOYMENTS / "valid" / deployment_name)
    return compile_edge(contract, deployment), contract, deployment


def loopback_contract(base_name: str, host: str = "127.0.0.1") -> dict[str, Any]:
    contract = load_json(CONTRACTS / "valid" / base_name)
    contract["public_origin"] = {"scheme": "http", "host": host}
    return contract


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])
