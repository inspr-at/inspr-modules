from __future__ import annotations

import http.client
import os
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACKAGE_ROOT))

from echo_backend import start_echo  # noqa: E402
from helpers import free_port, load_json, loopback_contract  # noqa: E402
from routing_edge.compile import compile_edge, write_outputs  # noqa: E402
from routing_edge.deployment import PINNED_TRAEFIK_VERSION  # noqa: E402
from routing_edge.yaml_emit import emit_yaml  # noqa: E402


TMP_ROOT = PACKAGE_ROOT / "tests" / ".tmp"


def traefik_binary() -> Path | None:
    env = os.environ.get("INSPR_TRAEFIK_BIN")
    if env:
        candidate = Path(env)
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    which = shutil.which("traefik")
    if which:
        candidate = Path(which)
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    return None


def require_traefik() -> Path:
    binary = traefik_binary()
    if binary is None:
        raise RuntimeError(
            f"Traefik {PINNED_TRAEFIK_VERSION} required for process integration proof: "
            "set INSPR_TRAEFIK_BIN or install traefik on PATH"
        )
    output = subprocess.check_output([str(binary), "version"], text=True)
    version_line = re.search(r"(?m)^Version:\s*([^\s]+)\s*$", output)
    if version_line is None or version_line.group(1) != PINNED_TRAEFIK_VERSION:
        raise RuntimeError(
            f"Traefik binary is not {PINNED_TRAEFIK_VERSION}: {output.strip()!r}"
        )
    return binary


def request(
    port: int,
    path: str,
    *,
    host: str = "127.0.0.1",
    headers: dict[str, str] | None = None,
    timeout: float = 8.0,
    tls: bool = False,
) -> tuple[int, dict[str, str], bytes]:
    connection_type = http.client.HTTPSConnection if tls else http.client.HTTPConnection
    kwargs = {"context": ssl._create_unverified_context()} if tls else {}
    connection = connection_type("127.0.0.1", port, timeout=timeout, **kwargs)
    try:
        merged = {"Host": host}
        if headers:
            merged.update(headers)
        connection.request("GET", path, headers=merged)
        response = connection.getresponse()
        body = response.read()
        return response.status, {key.lower(): value for key, value in response.getheaders()}, body
    finally:
        connection.close()


def wait_ready(
    port: int,
    process: subprocess.Popen[str],
    path: str,
    acceptable: set[int],
    timeout: float = 8.0,
    *,
    host: str = "127.0.0.1",
    tls: bool = False,
) -> None:
    deadline = time.time() + timeout
    last: int | None = None
    while time.time() < deadline:
        if process.poll() is not None:
            raise TimeoutError(f"traefik exited {process.returncode}")
        try:
            status, _, _ = request(port, path, host=host, tls=tls)
            if status in acceptable:
                return
            last = status
        except OSError:
            last = None
        time.sleep(0.05)
    raise TimeoutError(f"path {path} last status {last}")


class TraefikProcessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        TMP_ROOT.mkdir(parents=True, exist_ok=True)
        cls.binary = require_traefik()

    def _start_edge(self, contract_name: str, apps: tuple[str, ...], probe_path: str, probe_statuses: set[int]):
        contract = loopback_contract(contract_name)
        backends = {}
        upstreams = {}
        for app_id in apps:
            port = free_port()
            server, state = start_echo(app_id, port)
            backends[app_id] = {"server": server, "state": state, "port": port}
            upstreams[app_id] = {"url": f"http://127.0.0.1:{port}"}
        edge_port = free_port()
        deployment = {
            "loopback_http_fixture": True,
            "entrypoint": {"name": "web", "address": f"127.0.0.1:{edge_port}"},
            "upstreams": upstreams,
        }
        result = compile_edge(contract, deployment)
        self.assertEqual(result.findings, [], [str(item) for item in result.findings])
        tmp = tempfile.TemporaryDirectory(prefix="inspr-387-", dir=TMP_ROOT)
        write_outputs(result, Path(tmp.name))
        log_path = Path(tmp.name) / "traefik.log"
        log_file = log_path.open("w", encoding="utf-8")
        process = subprocess.Popen(
            [str(self.binary), "--configFile", str(Path(tmp.name) / "static.yml")],
            cwd=tmp.name,
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )
        try:
            wait_ready(edge_port, process, probe_path, probe_statuses)
        except TimeoutError as error:
            process.terminate()
            process.wait(timeout=5)
            log_file.flush()
            raise AssertionError(f"{error}\n{log_path.read_text(encoding='utf-8')}")
        return {
            "port": edge_port,
            "backends": backends,
            "tmp": tmp,
            "process": process,
            "log_path": log_path,
            "log_file": log_file,
            "result": result,
        }

    def _stop(self, bundle: dict) -> None:
        process = bundle["process"]
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        log_file = bundle.get("log_file")
        if log_file is not None:
            log_file.close()
        for item in bundle["backends"].values():
            item["server"].shutdown()
            item["server"].server_close()
        bundle["tmp"].cleanup()

    def test_connected_paths_query_callbacks_denies_and_sse(self) -> None:
        bundle = self._start_edge(
            "combined-connected.json",
            ("aithema", "paimos", "pharos", "janus"),
            "/aithema",
            {200},
        )
        try:
            port = bundle["port"]
            status, headers, body = request(port, "/aithema/oidc/callback?code=demo")
            self.assertEqual(status, 200)
            payload = _json(body)
            self.assertEqual(payload["app_id"], "aithema")
            self.assertEqual(payload["path"], "/aithema/oidc/callback")
            self.assertEqual(payload["query"], "code=demo")
            self.assertEqual(payload["host"], "127.0.0.1")
            self.assertEqual(payload["x_forwarded_user"], None)

            status, _, body = request(
                port,
                "/paimos/api/auth/oidc/callback?state=abc",
                headers={"X-Forwarded-User": "attacker", "X-Remote-User": "attacker"},
            )
            self.assertEqual(status, 200)
            payload = _json(body)
            self.assertEqual(payload["app_id"], "paimos")
            self.assertEqual(payload["path"], "/paimos/api/auth/oidc/callback")
            self.assertEqual(payload["query"], "state=abc")
            self.assertIn(payload["x_forwarded_user"], (None, ""))
            self.assertIn(payload["x_remote_user"], (None, ""))

            status, _, body = request(port, "/paimos/projects/demo/baseline-batches/flow-state?tab=flow")
            self.assertEqual(status, 200)
            payload = _json(body)
            self.assertEqual(payload["app_id"], "paimos")
            self.assertEqual(payload["query"], "tab=flow")

            status, _, _ = request(port, "/paimosx")
            self.assertEqual(status, 404)

            status, headers, _ = request(port, "/")
            self.assertIn(status, {302, 307, 308})
            self.assertTrue(headers.get("location", "").endswith("/aithema"))

            status, _, _ = request(port, "/paimos/api/control-commands/17")
            self.assertEqual(status, 403)
            status, _, _ = request(port, "/api/control-commands/17")
            self.assertEqual(status, 403)
            status, _, _ = request(port, "/pharos/metrics")
            self.assertEqual(status, 403)
            status, _, _ = request(port, "/janus/internal/managed-service-operations/op1/reconcile")
            self.assertEqual(status, 403)
            status, _, _ = request(port, "/aithema/session/demo")
            self.assertEqual(status, 403)

            # Security regression: encoded separators and dot segments must
            # never turn a public app path into another app's route or expose
            # an unpublished control endpoint after Traefik normalization.
            before = {
                app_id: len(item["state"].requests)
                for app_id, item in bundle["backends"].items()
            }
            for hostile_path in (
                "/paimos%2fapi%2fcontrol-commands%2f17",
                "/paimos/%2e%2e/aithema/session/demo",
            ):
                status, _, _ = request(port, hostile_path)
                self.assertIn(status, {400, 403, 404}, hostile_path)
            self.assertEqual(
                {
                    app_id: len(item["state"].requests)
                    for app_id, item in bundle["backends"].items()
                },
                before,
            )

            first_at = _sse_first_byte_delay(port, "/paimos/api/intake/sessions/demo/stream")
            self.assertLess(first_at, 0.35)
        finally:
            self._stop(bundle)

    def test_root_app_near_misses_and_disabled_vocabulary(self) -> None:
        bundle = self._start_edge(
            "combined-aithema-root.json",
            ("aithema", "paimos", "pharos"),
            "/",
            {200},
        )
        try:
            port = bundle["port"]
            status, _, body = request(port, "/")
            self.assertEqual(status, 200)
            self.assertEqual(_json(body)["app_id"], "aithema")

            status, _, body = request(port, "/paimos/api/health")
            self.assertEqual(status, 200)
            self.assertEqual(_json(body)["app_id"], "paimos")

            status, _, body = request(port, "/paimosx")
            self.assertEqual(status, 200)
            self.assertEqual(_json(body)["app_id"], "aithema")

            status, _, _ = request(port, "/janus/login")
            self.assertEqual(status, 403)

            status, _, _ = request(port, "/paimos/api/auth/dev-login")
            self.assertEqual(status, 403)
        finally:
            self._stop(bundle)

    def test_standalone_does_not_publish_disconnected_prefixes(self) -> None:
        bundle = self._start_edge("standalone-aithema.json", ("aithema",), "/", {200})
        try:
            port = bundle["port"]
            status, _, body = request(port, "/oidc/callback")
            self.assertEqual(status, 200)
            self.assertEqual(_json(body)["app_id"], "aithema")
            status, _, _ = request(port, "/paimos/api/health")
            self.assertEqual(status, 403)
        finally:
            self._stop(bundle)

    def test_external_fragment_loads_beside_consumer_file_on_existing_tls_edge(self) -> None:
        contract = load_json(
            PACKAGE_ROOT.parents[1] / "contracts/routing/fixtures/valid/combined-connected.json"
        )
        contract["public_origin"] = {"scheme": "https", "host": "edge.fixture.test"}
        backends = {}
        upstreams = {}
        for app_id in ("aithema", "paimos", "pharos", "janus"):
            backend_port = free_port()
            server, state = start_echo(app_id, backend_port)
            backends[app_id] = {"server": server, "state": state, "port": backend_port}
            upstreams[app_id] = {"url": f"http://127.0.0.1:{backend_port}"}

        edge_port = free_port()
        deployment = {
            "mode": "external-file-provider",
            "entrypoint": {"name": "existing-websecure"},
            "certificate_resolver": "existing-acme",
            "resource_namespace": "fixture-edge",
            "upstreams": upstreams,
        }
        result = compile_edge(contract, deployment)
        self.assertEqual(result.findings, [], [str(item) for item in result.findings])
        self.assertEqual(result.static_yaml, "")

        tmp = tempfile.TemporaryDirectory(prefix="inspr-389-", dir=TMP_ROOT)
        root = Path(tmp.name)
        provider_dir = root / "provider"
        staging_dir = root / "staging"
        provider_dir.mkdir()
        write_outputs(result, staging_dir)
        shutil.copyfile(staging_dir / "dynamic.yml", provider_dir / "fixture-edge.yml")

        cert_file = root / "synthetic.crt"
        key_file = root / "synthetic.key"
        subprocess.run(
            [
                "/usr/bin/openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "1",
                "-subj",
                "/CN=edge.fixture.test",
                "-addext",
                "subjectAltName=DNS:edge.fixture.test",
                "-keyout",
                str(key_file),
                "-out",
                str(cert_file),
            ],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

        consumer_dynamic = {
            "http": {
                "routers": {
                    "consumer-owned-router": {
                        "rule": "Host(`edge.fixture.test`) && Path(`/consumer-owned`)",
                        "entryPoints": ["existing-websecure"],
                        "service": "consumer-owned-service",
                        "tls": {},
                    }
                },
                "services": {
                    "consumer-owned-service": {
                        "loadBalancer": {
                            "servers": [{"url": f"http://127.0.0.1:{backends['aithema']['port']}"}]
                        }
                    }
                },
            },
            "tls": {"certificates": [{"certFile": str(cert_file), "keyFile": str(key_file)}]},
        }
        (provider_dir / "consumer.yml").write_text(emit_yaml(consumer_dynamic), encoding="utf-8")

        static = {
            "global": {"checkNewVersion": False, "sendAnonymousUsage": False},
            "log": {"level": "ERROR"},
            "entryPoints": {
                "existing-websecure": {
                    "address": f"127.0.0.1:{edge_port}",
                    "transport": {
                        "respondingTimeouts": {
                            "readTimeout": "0s",
                            "writeTimeout": "0s",
                            "idleTimeout": "180s",
                        }
                    },
                }
            },
            "providers": {"file": {"directory": str(provider_dir), "watch": False}},
            "certificatesResolvers": {
                "existing-acme": {
                    "acme": {
                        "caServer": "https://127.0.0.1:1/directory",
                        "storage": str(root / "synthetic-acme.json"),
                        "tlsChallenge": {},
                    }
                }
            },
        }
        static_file = root / "consumer-static.yml"
        static_file.write_text(emit_yaml(static), encoding="utf-8")
        log_path = root / "traefik.log"
        log_file = log_path.open("w", encoding="utf-8")
        process = subprocess.Popen(
            [str(self.binary), "--configFile", str(static_file)],
            cwd=root,
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )
        bundle = {
            "backends": backends,
            "tmp": tmp,
            "process": process,
            "log_file": log_file,
        }
        try:
            wait_ready(
                edge_port,
                process,
                "/aithema/assets/app.js",
                {200},
                host="edge.fixture.test",
                tls=True,
            )
            for path, app_id in (
                ("/aithema/assets/app.js", "aithema"),
                ("/paimos/api/health", "paimos"),
                ("/consumer-owned", "aithema"),
            ):
                status, _, body = request(
                    edge_port, path, host="edge.fixture.test", tls=True
                )
                self.assertEqual(status, 200)
                payload = _json(body)
                self.assertEqual(payload["app_id"], app_id)
                self.assertEqual(payload["path"], path)

            status, _, body = request(
                edge_port,
                "/paimos/api/auth/oidc/callback",
                host="edge.fixture.test",
                headers={"X-Forwarded-User": "attacker", "X-Remote-User": "attacker"},
                tls=True,
            )
            self.assertEqual(status, 200)
            payload = _json(body)
            self.assertIn(payload["x_forwarded_user"], (None, ""))
            self.assertIn(payload["x_remote_user"], (None, ""))

            for denied in (
                "/paimos/api/control-commands/17",
                "/api/control-commands/17",
                "/pharos/metrics",
                "/janus/internal/reconcile",
                "/aithema/session/demo",
            ):
                status, _, _ = request(
                    edge_port, denied, host="edge.fixture.test", tls=True
                )
                self.assertEqual(status, 403, denied)

            first_at = _sse_first_byte_delay(
                edge_port,
                "/paimos/api/intake/sessions/demo/stream",
                host="edge.fixture.test",
                tls=True,
            )
            self.assertLess(first_at, 0.35)
        except Exception as error:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=5)
            log_file.flush()
            raise AssertionError(
                f"{error}\n{log_path.read_text(encoding='utf-8')}"
            ) from error
        finally:
            self._stop(bundle)


def _json(body: bytes) -> dict:
    import json

    return json.loads(body.decode("utf-8"))


def _sse_first_byte_delay(
    port: int,
    path: str,
    *,
    host: str = "127.0.0.1",
    tls: bool = False,
) -> float:
    connection_type = http.client.HTTPSConnection if tls else http.client.HTTPConnection
    kwargs = {"context": ssl._create_unverified_context()} if tls else {}
    connection = connection_type("127.0.0.1", port, timeout=8, **kwargs)
    started = time.monotonic()
    try:
        connection.request("GET", path, headers={"Host": host, "Accept": "text/event-stream"})
        response = connection.getresponse()
        self_status = response.status
        if self_status != 200:
            raise AssertionError(f"SSE status {self_status}")
        buf = b""
        while b"data: first" not in buf:
            chunk = response.read(1)
            if not chunk:
                raise AssertionError(f"SSE closed before first event: {buf!r}")
            buf += chunk
        return time.monotonic() - started
    finally:
        connection.close()


if __name__ == "__main__":
    unittest.main()
