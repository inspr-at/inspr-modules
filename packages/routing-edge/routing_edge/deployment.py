"""Bounded operator deployment inputs for the routing-edge compiler."""

from __future__ import annotations

import ipaddress
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

import sys

CONTRACT_ROOT = Path(__file__).resolve().parents[3] / "contracts" / "routing"
sys.path.insert(0, str(CONTRACT_ROOT))
from validate import APP_IDS, Finding, HOSTNAME  # noqa: E402


PINNED_TRAEFIK_VERSION = "3.7.13"
PINNED_TRAEFIK_SYNTAX = "file-provider-v3.7.13"
PINNED_TRAEFIK_RELEASE = "https://github.com/traefik/traefik/releases/tag/v3.7.13"
PINNED_TRAEFIK_OCI_IMAGE = "docker.io/library/traefik"
PINNED_TRAEFIK_OCI_INDEX_DIGEST = (
    "sha256:f86a2cab1b5c649070c49f883c743dd32d8485a56e3368c5f93b9e91f1e91259"
)
PINNED_TRAEFIK_OCI_LINUX_AMD64_DIGEST = (
    "sha256:96780238b1bbda5a9bb997f4307ce69e798ad1cf6eb7f2dcc0a440823467d199"
)
MANAGED_MODE = "managed"
EXTERNAL_MODE = "external-file-provider"
DEPLOYMENT_MODES = {MANAGED_MODE, EXTERNAL_MODE}
ENTRYPOINT_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,32}$")
RESOURCE_NAMESPACE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]{0,47}$")
ENTRYPOINT_ADDRESS = re.compile(r"^(?:127\.0\.0\.1|localhost)?:[0-9]{1,5}$")
LOOPBACK_HOSTS = {"localhost", "localhost.", "127.0.0.1"}
CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]")
PEM_MARKER = "-----BEGIN"


@dataclass(frozen=True)
class UpstreamInput:
    app_id: str
    url: str
    origin: str
    scheme: str
    host: str
    port: int | None
    ca_file: str | None


@dataclass(frozen=True)
class DeploymentInput:
    mode: str
    loopback_http_fixture: bool
    entrypoint_name: str
    entrypoint_address: str | None
    certificate_resolver: str | None
    resource_namespace: str
    cert_file: str | None
    key_file: str | None
    upstreams: dict[str, UpstreamInput]


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def parse_deployment(document: Any) -> tuple[DeploymentInput | None, list[Finding]]:
    findings: list[Finding] = []

    def add(code: str, path: str, message: str) -> None:
        findings.append(Finding(code, path, message))

    if not isinstance(document, dict):
        add("MALFORMED_DEPLOYMENT", "$", "deployment document must be an object")
        return None, findings

    mode = document.get("mode", MANAGED_MODE)
    if not isinstance(mode, str) or mode not in DEPLOYMENT_MODES:
        add(
            "MALFORMED_DEPLOYMENT",
            "$.mode",
            f"mode must be one of {sorted(DEPLOYMENT_MODES)}",
        )
        return None, findings

    common_fields = {"mode", "entrypoint", "upstreams"}
    mode_fields = (
        {"loopback_http_fixture", "public_tls"}
        if mode == MANAGED_MODE
        else {"certificate_resolver", "resource_namespace"}
    )
    if extra := sorted(set(document) - common_fields - mode_fields):
        add("UNSUPPORTED_WIRING", "$", f"fields incompatible with {mode} mode: {extra}")

    fixture = document.get("loopback_http_fixture", False)
    if not isinstance(fixture, bool):
        add("MALFORMED_DEPLOYMENT", "$.loopback_http_fixture", "must be boolean")
        fixture = False

    entry = document.get("entrypoint")
    if not isinstance(entry, dict):
        add("MALFORMED_DEPLOYMENT", "$.entrypoint", "expected object")
        entry = {}
    name = entry.get("name")
    address = entry.get("address")
    if mode == EXTERNAL_MODE and (extra := sorted(set(entry) - {"name"})):
        add(
            "UNSUPPORTED_WIRING",
            "$.entrypoint",
            f"fields incompatible with {mode} mode: {extra}",
        )
    if not isinstance(name, str) or not ENTRYPOINT_NAME.fullmatch(name):
        add("MALFORMED_DEPLOYMENT", "$.entrypoint.name", "entrypoint name must be a short identifier")
    if mode == MANAGED_MODE:
        if not isinstance(address, str) or not ENTRYPOINT_ADDRESS.fullmatch(address):
            add("MALFORMED_DEPLOYMENT", "$.entrypoint.address", "entrypoint address must be :port or 127.0.0.1:port")
        else:
            port = int(address.rsplit(":", 1)[1])
            if port < 1 or port > 65535:
                add("MALFORMED_DEPLOYMENT", "$.entrypoint.address", "entrypoint port out of range")
    else:
        address = None

    certificate_resolver = document.get("certificate_resolver")
    resource_namespace = document.get("resource_namespace")
    if mode == EXTERNAL_MODE:
        if not isinstance(certificate_resolver, str) or not ENTRYPOINT_NAME.fullmatch(certificate_resolver):
            add(
                "MALFORMED_DEPLOYMENT",
                "$.certificate_resolver",
                "existing certificate resolver must be a short identifier",
            )
        if not isinstance(resource_namespace, str) or not RESOURCE_NAMESPACE.fullmatch(resource_namespace):
            add(
                "MALFORMED_DEPLOYMENT",
                "$.resource_namespace",
                "resource namespace must be a short identifier",
            )
    else:
        certificate_resolver = None
        resource_namespace = "inspr"

    cert_file = None
    key_file = None
    tls = document.get("public_tls")
    if mode == MANAGED_MODE:
        if tls is None:
            if not fixture:
                add("TLS_REQUIRED", "$.public_tls", "public operation requires explicit cert_file and key_file paths")
        elif not isinstance(tls, dict):
            add("MALFORMED_DEPLOYMENT", "$.public_tls", "expected object")
        else:
            if tls.keys() - {"cert_file", "key_file"}:
                add("MALFORMED_DEPLOYMENT", "$.public_tls", "only cert_file and key_file are accepted")
            cert_file = tls.get("cert_file")
            key_file = tls.get("key_file")
            cert_file = _path_input(cert_file, "$.public_tls.cert_file", add)
            key_file = _path_input(key_file, "$.public_tls.key_file", add)
            if fixture and (cert_file or key_file):
                add("UNSUPPORTED_WIRING", "$.public_tls", "loopback HTTP fixture mode must not carry TLS files")

    upstreams_raw = document.get("upstreams")
    if not isinstance(upstreams_raw, dict):
        add("MALFORMED_DEPLOYMENT", "$.upstreams", "expected object")
        upstreams_raw = {}
    unknown = sorted(set(upstreams_raw) - set(APP_IDS))
    if extra_apps := unknown:
        add("MALFORMED_DEPLOYMENT", "$.upstreams", f"unknown apps: {extra_apps}")

    parsed: dict[str, UpstreamInput] = {}
    for app_id, spec in upstreams_raw.items():
        if app_id not in APP_IDS:
            continue
        origin = _parse_upstream(app_id, spec, add)
        if origin is not None:
            parsed[app_id] = origin

    if findings:
        return None, findings
    return (
        DeploymentInput(
            mode=mode,
            loopback_http_fixture=fixture,
            entrypoint_name=name,
            entrypoint_address=address,
            certificate_resolver=certificate_resolver,
            resource_namespace=resource_namespace,
            cert_file=cert_file,
            key_file=key_file,
            upstreams=parsed,
        ),
        findings,
    )


def _path_input(value: Any, path: str, add) -> str | None:
    if not isinstance(value, str) or not value or value.strip() != value:
        add("MALFORMED_DEPLOYMENT", path, "path must be a non-empty string")
        return None
    if CONTROL_CHARS.search(value) or "\n" in value:
        add("MALFORMED_DEPLOYMENT", path, "path must not contain control characters")
        return None
    if PEM_MARKER in value:
        add("MALFORMED_DEPLOYMENT", path, "TLS material must be a filesystem path, not PEM content")
        return None
    if value.startswith("~") or value.startswith("file:"):
        add("MALFORMED_DEPLOYMENT", path, "path must be an explicit absolute filesystem path")
        return None
    if not value.startswith("/"):
        add("MALFORMED_DEPLOYMENT", path, "path must be absolute")
        return None
    return value


def _parse_upstream(app_id: str, spec: Any, add) -> UpstreamInput | None:
    path = f"$.upstreams.{app_id}"
    if not isinstance(spec, dict) or spec.keys() - {"url", "ca_file"}:
        add("MALFORMED_DEPLOYMENT", path, "upstream must only declare url and optional ca_file")
        return None
    url = spec.get("url")
    if not isinstance(url, str) or not url:
        add("MALFORMED_DEPLOYMENT", f"{path}.url", "url is required")
        return None
    if CONTROL_CHARS.search(url):
        add("MALFORMED_DEPLOYMENT", f"{path}.url", "url must not contain control characters")
        return None
    parsed = urlsplit(url)
    if parsed.username is not None or parsed.password is not None or "@" in (parsed.netloc or ""):
        add("UPSTREAM_USERINFO", f"{path}.url", "upstream URLs must not contain userinfo/credentials")
        return None
    if parsed.query:
        add("UPSTREAM_QUERY", f"{path}.url", "upstream URLs must not contain a query")
        return None
    if parsed.fragment:
        add("UPSTREAM_FRAGMENT", f"{path}.url", "upstream URLs must not contain a fragment")
        return None
    if parsed.scheme not in {"http", "https"}:
        add("UNSUPPORTED_WIRING", f"{path}.url", "upstream scheme must be http or https")
        return None
    if parsed.path not in {"", "/"}:
        add("UNSUPPORTED_WIRING", f"{path}.url", "upstream URL must be origin-only; request paths are preserved by the edge")
        return None
    hostname = parsed.hostname
    if hostname is None or not hostname:
        add("MALFORMED_DEPLOYMENT", f"{path}.url", "upstream host is missing")
        return None
    host_header = parsed.netloc
    if not HOSTNAME.fullmatch(host_header) and hostname not in LOOPBACK_HOSTS:
        # urlsplit lowercase + IPv6 brackets. Allow loopback IPv4 and parsed hostname:port.
        if not _looks_like_host(hostname, parsed.port):
            add("MALFORMED_DEPLOYMENT", f"{path}.url", "upstream host is not a usable hostname")
            return None
    ca_file = spec.get("ca_file")
    if ca_file is not None:
        ca_file = _path_input(ca_file, f"{path}.ca_file", add)
        if parsed.scheme != "https":
            add("UNSUPPORTED_WIRING", f"{path}.ca_file", "ca_file is only valid for https upstreams")
    return UpstreamInput(
        app_id=app_id,
        url=url,
        origin=f"{parsed.scheme}://{parsed.netloc}",
        scheme=parsed.scheme,
        host=hostname,
        port=parsed.port,
        ca_file=ca_file,
    )


def _looks_like_host(hostname: str, port: int | None) -> bool:
    if hostname in LOOPBACK_HOSTS:
        return True
    try:
        ipaddress.ip_address(hostname)
        return True
    except ValueError:
        return bool(HOSTNAME.fullmatch(hostname if port is None else f"{hostname}:{port}"))


def is_loopback_host(host: str) -> bool:
    hostname = host.split("%", 1)[0]
    if hostname.lower() in LOOPBACK_HOSTS or hostname.lower() == "::1":
        return True
    try:
        return ipaddress.ip_address(hostname).is_loopback
    except ValueError:
        return False


def is_private_or_loopback_host(host: str) -> bool:
    if is_loopback_host(host):
        return True
    try:
        address = ipaddress.ip_address(host.split("%", 1)[0])
    except ValueError:
        return False
    if address.is_loopback or address.is_link_local:
        return True
    if isinstance(address, ipaddress.IPv4Address):
        return any(
            address in network
            for network in (
                ipaddress.ip_network("10.0.0.0/8"),
                ipaddress.ip_network("172.16.0.0/12"),
                ipaddress.ip_network("192.168.0.0/16"),
            )
        )
    return isinstance(address, ipaddress.IPv6Address) and address in ipaddress.ip_network("fc00::/7")
