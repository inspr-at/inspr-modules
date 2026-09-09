from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path
from typing import Any


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACKAGE_ROOT))

from validate import (  # noqa: E402
    CONTRACT_VERSION,
    DEFAULT_CONNECTED_PATHS,
    join_public_path,
    normalize_public_base_path,
    public_url,
    validate_document,
    validate_return_target,
)


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


class RoutingContractTests(unittest.TestCase):
    def test_schema_declares_draft_and_closed_additional_properties(self) -> None:
        schema = load_json(PACKAGE_ROOT / "schema/routing.schema.json")
        self.assertEqual(schema["$schema"], "https://json-schema.org/draft/2020-12/schema")
        self.assertEqual(schema["properties"]["contract_version"]["const"], CONTRACT_VERSION)
        self.assertEqual(schema["additionalProperties"], False)
        self.assertEqual(schema["$defs"]["edge"]["properties"]["mode"]["const"], "prefix_preserving_proxy")

    def test_all_valid_fixtures_conform(self) -> None:
        for fixture_path in sorted((PACKAGE_ROOT / "fixtures/valid").glob("*.json")):
            with self.subTest(fixture=fixture_path.name):
                self.assertEqual(validate_document(load_json(fixture_path)), [])

    def test_invalid_fixtures_fail_for_their_named_invariants(self) -> None:
        for fixture_path in sorted((PACKAGE_ROOT / "fixtures/invalid").glob("*.patch.json")):
            with self.subTest(fixture=fixture_path.name):
                document, expected_codes = apply_fixture_patch(fixture_path)
                actual_codes = {finding.code for finding in validate_document(document)}
                self.assertTrue(
                    expected_codes <= actual_codes,
                    f"expected {sorted(expected_codes)}, got {sorted(actual_codes)}",
                )

    def test_default_connected_paths_are_documented_vocabulary(self) -> None:
        document = load_json(PACKAGE_ROOT / "fixtures/valid/combined-connected.json")
        for app_id, default_path in DEFAULT_CONNECTED_PATHS.items():
            self.assertEqual(document["apps"][app_id]["public_base_path"], default_path)

    def test_join_public_path_preserves_query_separately(self) -> None:
        joined = join_public_path("/paimos", "/api/auth/oidc/callback")
        self.assertEqual(joined, "/paimos/api/auth/oidc/callback")
        url = public_url(
            {"scheme": "https", "host": "apps.fixture.test"},
            "/paimos",
            "/api/auth/oidc/callback",
            {"next": "/projects/demo"},
        )
        self.assertEqual(
            url,
            "https://apps.fixture.test/paimos/api/auth/oidc/callback?next=%2Fprojects%2Fdemo",
        )

    def test_join_public_path_rejects_duplicate_prefix(self) -> None:
        with self.assertRaises(ValueError):
            join_public_path("/paimos", "/paimos/api/auth/oidc/callback")

    def test_normalize_public_base_path_rejects_trailing_slash(self) -> None:
        with self.assertRaises(ValueError):
            normalize_public_base_path("/paimos/")

    def test_validate_return_target_rejects_foreign_origin(self) -> None:
        origin = {"scheme": "https", "host": "apps.fixture.test"}
        findings = validate_return_target(origin, "/paimos", "https://evil.example.test/steal")
        self.assertTrue(any(finding.code == "OPEN_REDIRECT" for finding in findings))

    def test_validate_return_target_rejects_protocol_relative_target(self) -> None:
        origin = {"scheme": "https", "host": "apps.fixture.test"}
        findings = validate_return_target(origin, "/paimos", "//evil.example.test/x")
        self.assertTrue(any(finding.code == "OPEN_REDIRECT" for finding in findings))

    def test_validate_return_target_rejects_path_escape(self) -> None:
        origin = {"scheme": "https", "host": "apps.fixture.test"}
        findings = validate_return_target(origin, "/paimos", "/paimos/../pharos/hijack")
        self.assertTrue(any(finding.code == "PATH_ESCAPE" for finding in findings))

    def test_validate_return_target_accepts_same_origin_relative_path(self) -> None:
        origin = {"scheme": "https", "host": "apps.fixture.test"}
        findings = validate_return_target(origin, "/paimos", "/projects/demo?tab=flow")
        self.assertEqual(findings, [])

    def test_standalone_fixture_keeps_empty_default_compatible(self) -> None:
        document = load_json(PACKAGE_ROOT / "fixtures/valid/standalone-aithema.json")
        self.assertEqual(document["apps"]["aithema"]["public_base_path"], "")
        self.assertEqual(join_public_path("", "/oidc/callback"), "/oidc/callback")


if __name__ == "__main__":
    unittest.main()
