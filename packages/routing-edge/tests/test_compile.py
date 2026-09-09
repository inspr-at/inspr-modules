from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACKAGE_ROOT))

from routing_edge.compile import compile_edge, write_outputs  # noqa: E402
from routing_edge.deny import deny_regexes_for_app, route_regex  # noqa: E402
from routing_edge.deployment import (  # noqa: E402
    PINNED_TRAEFIK_OCI_INDEX_DIGEST,
    PINNED_TRAEFIK_OCI_LINUX_AMD64_DIGEST,
    PINNED_TRAEFIK_RELEASE,
    PINNED_TRAEFIK_VERSION,
)
from helpers import (  # noqa: E402
    DEPLOYMENTS,
    apply_fixture_patch,
    compile_named,
    load_json,
    loopback_contract,
)


class CompileTests(unittest.TestCase):
    def _external_deployment(self) -> dict:
        deployment = load_json(DEPLOYMENTS / "valid" / "combined-connected.deployment.json")
        deployment.pop("public_tls")
        deployment["mode"] = "external-file-provider"
        deployment["entrypoint"] = {"name": "existing-websecure"}
        deployment["certificate_resolver"] = "existing-acme"
        deployment["resource_namespace"] = "fixture-edge"
        return deployment

    def test_connected_fixture_preserves_prefixes_and_pins_traefik(self) -> None:
        result, contract, _deployment = compile_named(
            "combined-connected.json",
            "combined-connected.deployment.json",
        )
        self.assertEqual(result.findings, [])
        yaml = result.dynamic_yaml
        self.assertIn(PINNED_TRAEFIK_VERSION, yaml)
        self.assertNotIn("stripPrefix", yaml)
        self.assertNotIn("StripPrefix", yaml)
        self.assertNotIn("Access-Control-Allow-Origin", yaml)
        self.assertNotIn("buffering:", yaml)
        self.assertNotIn("insecureSkipVerify", yaml)
        self.assertIn("passHostHeader: true", yaml)
        self.assertIn("responseHeaderTimeout: \"0s\"", yaml)
        self.assertIn("Host(`apps.fixture.test`)", yaml)
        self.assertIn("PathRegexp(`^/paimos(?:/.*)?$`)", yaml)
        self.assertIn("PathRegexp(`^/aithema(?:/.*)?$`)", yaml)
        self.assertIn("/paimos/api/auth/oidc/callback", result.report["apps"]["paimos"]["oidc_redirect_url"])
        self.assertEqual(result.report["strip_prefix"], False)
        self.assertEqual(result.report["sso_verified"], False)
        self.assertEqual(result.report["operator_secrets_exported"], False)
        self.assertEqual(result.report["traefik"]["version"], PINNED_TRAEFIK_VERSION)
        self.assertEqual(result.report["traefik"]["release"], PINNED_TRAEFIK_RELEASE)
        self.assertEqual(
            result.report["traefik"]["process_proof_oci"]["index_digest"],
            PINNED_TRAEFIK_OCI_INDEX_DIGEST,
        )
        self.assertEqual(
            result.report["traefik"]["process_proof_oci"]["linux_amd64_digest"],
            PINNED_TRAEFIK_OCI_LINUX_AMD64_DIGEST,
        )
        self.assertTrue(result.dynamic["http"]["routers"]["inspr-app-paimos"]["priority"] > 50)
        self.assertIn("tls", result.dynamic["http"]["routers"]["inspr-app-paimos"])
        self.assertEqual(contract["contract_version"], "inspr.routing/0.1-draft")
        report_text = json.dumps(result.report)
        self.assertNotIn("BEGIN PRIVATE", report_text)
        self.assertNotIn("user:secret", report_text)

    def test_root_aithema_excludes_prefixed_peers_by_priority(self) -> None:
        result, _, _ = compile_named(
            "combined-aithema-root.json",
            "combined-aithema-root.deployment.json",
        )
        self.assertEqual(result.findings, [])
        routers = result.dynamic["http"]["routers"]
        self.assertEqual(routers["inspr-app-aithema"]["priority"], 10)
        self.assertGreater(routers["inspr-app-paimos"]["priority"], routers["inspr-app-aithema"]["priority"])
        self.assertIn("PathRegexp(`^/.*$`)", routers["inspr-app-aithema"]["rule"])
        self.assertIn("inspr-deny-disabled-vocabulary", routers)
        self.assertIn("/janus", routers["inspr-deny-disabled-vocabulary"]["rule"])
        self.assertNotIn("inspr-app-janus", routers)
        self.assertNotIn("janus", result.dynamic["http"]["services"]["inspr-upstream-aithema"]["loadBalancer"]["servers"][0]["url"])

    def test_standalone_does_not_proxy_disconnected_apps(self) -> None:
        result, _, _ = compile_named(
            "standalone-aithema.json",
            "standalone-aithema.deployment.json",
        )
        self.assertEqual(result.findings, [])
        routers = result.dynamic["http"]["routers"]
        self.assertIn("inspr-app-aithema", routers)
        self.assertNotIn("inspr-app-paimos", routers)
        self.assertIn("/paimos", routers["inspr-deny-disabled-vocabulary"]["rule"])
        self.assertEqual(result.report["apps"]["paimos"]["proxied"], False)
        self.assertEqual(
            result.report["apps"]["paimos"]["disconnected_external_origin"],
            "https://paimos.fixture.test",
        )

    def test_connected_landing_redirects_root(self) -> None:
        result, _, _ = compile_named(
            "combined-connected.json",
            "combined-connected.deployment.json",
        )
        self.assertEqual(result.findings, [])
        landing = result.dynamic["http"]["middlewares"]["inspr-landing-redirect"]["redirectRegex"]
        self.assertEqual(landing["replacement"], "https://apps.fixture.test/aithema")
        self.assertIn("Path(`/`)", result.dynamic["http"]["routers"]["inspr-landing"]["rule"])

    def test_invalid_deployments_fail_closed(self) -> None:
        contract = load_json(
            PACKAGE_ROOT.parents[1] / "contracts/routing/fixtures/valid/combined-connected.json"
        )
        # Aithema-root contract for disabled-app-upstream
        root_contract = load_json(
            PACKAGE_ROOT.parents[1] / "contracts/routing/fixtures/valid/combined-aithema-root.json"
        )
        for fixture_path in sorted((DEPLOYMENTS / "invalid").glob("*.patch.json")):
            with self.subTest(fixture=fixture_path.name):
                deployment, expected = apply_fixture_patch(fixture_path)
                document = root_contract if "aithema-root" in fixture_path.read_text(encoding="utf-8") or "disabled-app" in fixture_path.name else contract
                if "disabled-app" in fixture_path.name:
                    document = root_contract
                result = compile_edge(document, deployment)
                actual = {finding.code for finding in result.findings}
                self.assertTrue(expected <= actual, f"expected {sorted(expected)}, got {sorted(actual)}")
                self.assertFalse(result.ok)
                self.assertEqual(result.dynamic_yaml, "")

    def test_loopback_http_fixture_omits_tls_and_refuses_non_loopback(self) -> None:
        contract = loopback_contract("combined-connected.json")
        deployment = load_json(DEPLOYMENTS / "valid" / "loopback-http.deployment.json")
        result = compile_edge(contract, deployment)
        self.assertEqual(result.findings, [])
        self.assertNotIn("tls", result.dynamic)
        self.assertNotIn("tls", result.dynamic["http"]["routers"]["inspr-app-paimos"])

        bad = loopback_contract("combined-connected.json", host="apps.fixture.test")
        failed = compile_edge(bad, deployment)
        self.assertTrue(any(finding.code == "INSECURE_TOPOLOGY" for finding in failed.findings))

    def test_identity_headers_are_deleted_not_injected(self) -> None:
        result, _, _ = compile_named(
            "combined-connected.json",
            "combined-connected.deployment.json",
        )
        headers = result.dynamic["http"]["middlewares"]["inspr-drop-forwarded-identity"]["headers"]["customRequestHeaders"]
        self.assertEqual(headers["X-Forwarded-User"], "")
        self.assertEqual(headers["X-Remote-User"], "")
        self.assertIn('X-Forwarded-User: ""', result.dynamic_yaml)
        self.assertNotRegex(result.dynamic_yaml, r'X-Forwarded-User: "[^"]+')

    def test_optional_prefix_header_is_configured_not_request_chosen(self) -> None:
        result, _, _ = compile_named(
            "combined-connected.json",
            "combined-connected.deployment.json",
        )
        prefix = result.dynamic["http"]["middlewares"]["inspr-prefix-paimos"]["headers"]["customRequestHeaders"]
        self.assertEqual(prefix["X-Forwarded-Prefix"], "/paimos")

    def test_deny_catalog_covers_native_and_prefixed_control_paths(self) -> None:
        regexes = deny_regexes_for_app("paimos", "/paimos")
        self.assertIn(route_regex("", ("api", "control-commands", None)), regexes)
        self.assertIn(route_regex("/paimos", ("api", "control-commands", None)), regexes)
        joined = "\n".join(regexes)
        self.assertIn("/api/auth/dev-login", joined)
        self.assertIn("lifecycle/v1", joined)
        pharos = "\n".join(deny_regexes_for_app("pharos", "/pharos"))
        self.assertIn("/metrics", pharos)
        self.assertIn("/internal", pharos)
        janus = "\n".join(deny_regexes_for_app("janus", "/janus"))
        self.assertIn("/internal", janus)
        self.assertIn("/buildz", janus)

    def test_sse_paths_are_not_in_the_deny_catalog(self) -> None:
        deny = "\n".join(deny_regexes_for_app("paimos", "/paimos"))
        self.assertNotIn("intake/sessions/[^/]+/stream", deny)
        self.assertNotIn("/api/changes", deny)
        result, _, _ = compile_named("combined-connected.json", "combined-connected.deployment.json")
        self.assertIn("/paimos/api/changes", result.report["apps"]["paimos"]["sse"]["paths"])
        self.assertEqual(result.report["apps"]["paimos"]["sse"]["mode"], "stream-not-buffer")

    def test_wiring_report_does_not_copy_key_material(self) -> None:
        result, _, deployment = compile_named(
            "combined-connected.json",
            "combined-connected.deployment.json",
        )
        dumped = json.dumps(result.report)
        self.assertNotIn(deployment["public_tls"]["key_file"], dumped)

    def test_malformed_origin_in_contract_fails_before_generation(self) -> None:
        contract = load_json(
            PACKAGE_ROOT.parents[1] / "contracts/routing/fixtures/valid/combined-connected.json"
        )
        contract["public_origin"]["host"] = "apps.fixture.test/path"
        deployment = load_json(DEPLOYMENTS / "valid" / "combined-connected.deployment.json")
        result = compile_edge(contract, deployment)
        self.assertTrue(result.findings)
        self.assertEqual(result.dynamic_yaml, "")

    def test_explicit_managed_mode_preserves_legacy_output(self) -> None:
        contract = load_json(
            PACKAGE_ROOT.parents[1] / "contracts/routing/fixtures/valid/combined-connected.json"
        )
        deployment = load_json(DEPLOYMENTS / "valid" / "combined-connected.deployment.json")
        legacy = compile_edge(contract, deployment)
        explicit = compile_edge(contract, {"mode": "managed", **deployment})
        self.assertEqual(explicit.findings, [])
        self.assertEqual(explicit.dynamic_yaml, legacy.dynamic_yaml)
        self.assertEqual(explicit.static_yaml, legacy.static_yaml)
        self.assertEqual(explicit.report, legacy.report)

    def test_external_mode_emits_only_namespaced_dynamic_fragment(self) -> None:
        contract = load_json(
            PACKAGE_ROOT.parents[1] / "contracts/routing/fixtures/valid/combined-connected.json"
        )
        deployment = self._external_deployment()
        deployment["upstreams"]["paimos"]["ca_file"] = "/etc/traefik/upstream-ca.crt"
        result = compile_edge(contract, deployment)
        self.assertEqual(result.findings, [])
        self.assertEqual(result.static, {})
        self.assertEqual(result.static_yaml, "")
        self.assertNotIn("certificates", result.dynamic.get("tls", {}))
        self.assertTrue(all(name.startswith("fixture-edge-") for name in result.dynamic["http"]["routers"]))
        self.assertTrue(all(name.startswith("fixture-edge-") for name in result.dynamic["http"]["middlewares"]))
        self.assertTrue(all(name.startswith("fixture-edge-") for name in result.dynamic["http"]["services"]))
        self.assertEqual(
            result.dynamic["http"]["routers"]["fixture-edge-app-paimos"]["tls"],
            {"certResolver": "existing-acme"},
        )
        self.assertEqual(
            result.dynamic["http"]["serversTransports"]["fixture-edge-stream-paimos"]["rootCAs"],
            ["/etc/traefik/upstream-ca.crt"],
        )
        self.assertEqual(result.report["deployment_mode"], "external-file-provider")
        self.assertFalse(result.report["static_listener_generated"])
        self.assertFalse(result.report["public_tls_runtime_verified"])

    def test_external_mode_rejects_unknown_and_managed_only_inputs(self) -> None:
        contract = load_json(
            PACKAGE_ROOT.parents[1] / "contracts/routing/fixtures/valid/combined-connected.json"
        )
        for label, update in (
            ("unknown", {"mode": "hybrid"}),
            ("address", {"entrypoint": {"name": "websecure", "address": ":443"}}),
            ("tls", {"public_tls": {"cert_file": "/tmp/cert", "key_file": "/tmp/key"}}),
            ("fixture", {"loopback_http_fixture": True}),
        ):
            with self.subTest(label=label):
                deployment = self._external_deployment()
                deployment.update(update)
                result = compile_edge(contract, deployment)
                self.assertFalse(result.ok)
                self.assertEqual(result.dynamic_yaml, "")

    def test_external_replacement_removes_only_owned_stale_static(self) -> None:
        contract = load_json(
            PACKAGE_ROOT.parents[1] / "contracts/routing/fixtures/valid/combined-connected.json"
        )
        managed_deployment = load_json(DEPLOYMENTS / "valid" / "combined-connected.deployment.json")
        external = compile_edge(contract, self._external_deployment())
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            write_outputs(compile_edge(contract, managed_deployment), output)
            self.assertTrue((output / "static.yml").exists())
            write_outputs(external, output)
            self.assertFalse((output / "static.yml").exists())
            self.assertTrue((output / "dynamic.yml").exists())

            (output / "static.yml").write_text("consumer-owned\n", encoding="utf-8")
            before = (output / "dynamic.yml").read_text(encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "not owned"):
                write_outputs(external, output)
            self.assertEqual((output / "static.yml").read_text(encoding="utf-8"), "consumer-owned\n")
            self.assertEqual((output / "dynamic.yml").read_text(encoding="utf-8"), before)

        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "dynamic.yml").write_text("consumer-owned\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "not owned"):
                write_outputs(external, output)
            self.assertEqual((output / "dynamic.yml").read_text(encoding="utf-8"), "consumer-owned\n")


if __name__ == "__main__":
    unittest.main()
