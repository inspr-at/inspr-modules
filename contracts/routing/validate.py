#!/usr/bin/env python3
"""Focused semantic validator for the INSPR cross-app routing draft contract."""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


CONTRACT_VERSION = "inspr.routing/0.1-draft"
AUTHORITY_DISCLAIMER = (
    "Schema validity is not live proxy proof, SSO proof, or runtime authentication. "
    "Each app remains its own authority and OIDC client verifier."
)
APP_IDS = ("aithema", "paimos", "pharos", "janus")
DEFAULT_CONNECTED_PATHS = {
    "aithema": "/aithema",
    "paimos": "/paimos",
    "pharos": "/pharos",
    "janus": "/janus",
}
PUBLIC_BASE_PATH = re.compile(r"^(?:/[A-Za-z0-9_-]+)*$")
APP_RELATIVE_PATH = re.compile(
    r"^/(?:[A-Za-z0-9._~!$&'()*+,;=:@%-]+(?:/[A-Za-z0-9._~!$&'()*+,;=:@%-]+)*)?$"
)
HOSTNAME = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::[0-9]{1,5})?$")
CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f]")
ENCODED_DOT = re.compile(r"(?i)(?:%2e|\.)(?:%2e|\.)")


@dataclass(frozen=True)
class Finding:
    code: str
    path: str
    message: str

    def __str__(self) -> str:
        return f"{self.code}: {self.path}: {self.message}"


def _time(value: Any) -> datetime:
    if not isinstance(value, str):
        raise ValueError("timestamp is not a string")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def normalize_public_base_path(value: str) -> str:
    """Return canonical public base path: empty string or absolute ASCII path."""
    if value == "":
        return ""
    if not isinstance(value, str):
        raise ValueError("public base path must be a string")
    if value != "/" and value.endswith("/"):
        raise ValueError("public base path must not have a trailing slash")
    if not PUBLIC_BASE_PATH.fullmatch(value):
        raise ValueError("public base path segments must match [A-Za-z0-9_-]+")
    if "//" in value or "/." in value or "/.." in value:
        raise ValueError("public base path must not contain empty or dot segments")
    if CONTROL_CHARS.search(value) or "\\" in value or "%" in value:
        raise ValueError("public base path must be canonical ASCII without encoding")
    if "?" in value or "#" in value:
        raise ValueError("public base path must not include query or fragment")
    if value.startswith("//"):
        raise ValueError("public base path must not be protocol-relative")
    return value


def is_segment_prefix(path: str, prefix: str) -> bool:
    """True when path is exactly prefix or continues with a further segment."""
    normalized_path = normalize_app_relative_path(path)
    normalized_prefix = normalize_public_base_path(prefix)
    if normalized_prefix == "":
        return normalized_path.startswith("/")
    return normalized_path == normalized_prefix or normalized_path.startswith(normalized_prefix + "/")


def normalize_app_relative_path(value: str) -> str:
    if not isinstance(value, str) or not value.startswith("/"):
        raise ValueError("app-relative path must start with /")
    if value != "/" and value.endswith("/"):
        raise ValueError("app-relative path must not have a trailing slash")
    if not APP_RELATIVE_PATH.fullmatch(value):
        raise ValueError("app-relative path contains forbidden characters")
    if "//" in value or "/." in value or "/.." in value or ENCODED_DOT.search(value):
        raise ValueError("app-relative path must not contain dot segments or escapes")
    if CONTROL_CHARS.search(value) or "\\" in value:
        raise ValueError("app-relative path must be canonical ASCII")
    if "?" in value or "#" in value:
        raise ValueError("app-relative path must not include query or fragment")
    return value


def join_public_path(public_base_path: str, endpoint: str) -> str:
    """Join configured public base path and app-relative endpoint without duplicating prefix."""
    base = normalize_public_base_path(public_base_path)
    relative = normalize_app_relative_path(endpoint)
    if base == "":
        return relative
    if relative == "/":
        return base
    if relative.startswith(base + "/"):
        raise ValueError("endpoint already includes the configured public base path")
    return base + relative


def public_url(
    public_origin: dict[str, str],
    public_base_path: str,
    endpoint: str,
    query: dict[str, str] | None = None,
) -> str:
    """Build an absolute public URL on the configured origin."""
    scheme = public_origin["scheme"]
    host = public_origin["host"]
    path = join_public_path(public_base_path, endpoint)
    query_string = urlencode(sorted(query.items())) if query else ""
    return urlunsplit((scheme, host, path, query_string, ""))


def validate_return_target(
    public_origin: dict[str, str],
    public_base_path: str,
    target: str,
) -> list[Finding]:
    """Reject open redirects, foreign origins, and path escapes for same-origin returns."""
    findings: list[Finding] = []

    def add(code: str, path: str, message: str) -> None:
        findings.append(Finding(code, path, message))

    if not isinstance(target, str) or not target:
        add("MALFORMED_RETURN_TARGET", "$.return_target", "return target must be a non-empty string")
        return findings

    if target.startswith("//"):
        add("OPEN_REDIRECT", "$.return_target", "protocol-relative return targets are forbidden")
        return findings

    parsed = urlsplit(target)
    if parsed.scheme or parsed.netloc:
        if parsed.scheme not in {"http", "https"}:
            add("OPEN_REDIRECT", "$.return_target", "return target scheme must be http or https")
            return findings
        if parsed.hostname is None:
            add("OPEN_REDIRECT", "$.return_target", "return target host is missing")
            return findings
        expected_host = public_origin.get("host", "")
        expected_port = None
        if ":" in expected_host:
            host_part, port_part = expected_host.rsplit(":", 1)
            expected_host = host_part
            expected_port = port_part
        if parsed.hostname.lower() != expected_host.lower():
            add("OPEN_REDIRECT", "$.return_target", "return target host must match public_origin.host")
            return findings
        if expected_port is not None and str(parsed.port or "") != expected_port:
            add("OPEN_REDIRECT", "$.return_target", "return target port must match public_origin.host")
            return findings
        if parsed.scheme != public_origin.get("scheme"):
            add("OPEN_REDIRECT", "$.return_target", "return target scheme must match public_origin.scheme")
            return findings
        path = parsed.path or "/"
        query_items = parse_qsl(parsed.query, keep_blank_values=True)
    else:
        path = target.split("?", 1)[0]
        query_items = parse_qsl(target.split("?", 1)[1], keep_blank_values=True) if "?" in target else []

    try:
        normalized_target = normalize_app_relative_path(path if path.startswith("/") else f"/{path}")
    except ValueError as error:
        add("PATH_ESCAPE", "$.return_target", str(error))
        return findings

    try:
        joined = join_public_path(public_base_path, normalized_target)
        base = normalize_public_base_path(public_base_path)
    except ValueError as error:
        add("PATH_ESCAPE", "$.return_target", str(error))
        return findings

    if not is_segment_prefix(joined, base):
        add("PATH_ESCAPE", "$.return_target", "return target escapes the configured public base path")

    for key, value in query_items:
        if "://" in value or value.startswith("//"):
            add("OPEN_REDIRECT", "$.return_target", "return target query must not embed foreign origins")
            break
        if ENCODED_DOT.search(value):
            add("PATH_ESCAPE", "$.return_target", "return target query must not embed encoded dot segments")

    return findings


def validate_document(document: Any) -> list[Finding]:
    try:
        return _validate_document(document)
    except (TypeError, ValueError, AttributeError, KeyError) as error:
        return [Finding("MALFORMED_DOCUMENT", "$", f"document is not a usable routing contract: {error}")]


def _validate_document(document: Any) -> list[Finding]:
    findings: list[Finding] = []

    def add(code: str, path: str, message: str) -> None:
        findings.append(Finding(code, path, message))

    if not isinstance(document, dict):
        return [Finding("MALFORMED_DOCUMENT", "$", "document must be an object")]

    if document.get("contract_version") != CONTRACT_VERSION:
        add("UNSUPPORTED_VERSION", "$.contract_version", f"expected {CONTRACT_VERSION}")
    if document.get("authority_disclaimer") != AUTHORITY_DISCLAIMER:
        add("AUTHORITY_DISCLAIMER_REQUIRED", "$.authority_disclaimer", "exact non-proof disclaimer is required")

    try:
        _time(document.get("evaluated_at"))
    except (TypeError, ValueError):
        add("MALFORMED_DOCUMENT", "$.evaluated_at", "invalid RFC 3339 timestamp")

    public_origin = document.get("public_origin")
    if not isinstance(public_origin, dict):
        add("MALFORMED_DOCUMENT", "$.public_origin", "expected object")
        public_origin = {}
    else:
        scheme = public_origin.get("scheme")
        host = public_origin.get("host")
        if scheme not in {"http", "https"}:
            add("MALFORMED_DOCUMENT", "$.public_origin.scheme", "scheme must be http or https")
        if not isinstance(host, str) or not HOSTNAME.fullmatch(host):
            add("MALFORMED_DOCUMENT", "$.public_origin.host", "host must be scheme-less hostname with optional port")
        if "/" in host or "?" in host or "#" in host:
            add("MALFORMED_DOCUMENT", "$.public_origin.host", "host must not include a path, query, or fragment")

    landing = document.get("landing")
    landing_kind = None
    landing_app = None
    if not isinstance(landing, dict):
        add("MALFORMED_DOCUMENT", "$.landing", "expected object")
    else:
        landing_kind = landing.get("kind")
        if landing_kind not in {"aithema_workspace", "connected_default_app"}:
            add("MALFORMED_DOCUMENT", "$.landing.kind", "landing kind must be explicit")
        elif landing_kind == "connected_default_app":
            landing_app = landing.get("app")
            if landing_app not in APP_IDS:
                add("MALFORMED_DOCUMENT", "$.landing.app", "connected landing must name a known app")

    edge = document.get("edge")
    if not isinstance(edge, dict):
        add("MALFORMED_DOCUMENT", "$.edge", "expected object")
    else:
        if edge.get("mode") != "prefix_preserving_proxy":
            add("EDGE_MODE_INVALID", "$.edge.mode", "edge mode must be prefix_preserving_proxy")
        trust = edge.get("trust")
        if not isinstance(trust, dict):
            add("MALFORMED_DOCUMENT", "$.edge.trust", "expected object")
        else:
            for field in (
                "html_response_rewrite",
                "iframe_gateway",
                "permissive_cors",
                "forwarded_identity_trust",
                "shared_session_fallback",
            ):
                if trust.get(field) is not False:
                    add("FORBIDDEN_EDGE_TRUST", f"$.edge.trust.{field}", "forbidden edge trust pattern must remain false")

    apps = document.get("apps")
    if not isinstance(apps, dict):
        add("MALFORMED_DOCUMENT", "$.apps", "expected object")
        return findings

    enabled_roots: list[str] = []
    enabled_paths: dict[str, str] = {}
    client_refs: dict[str, str] = {}
    public_callbacks: dict[str, str] = {}

    for app_id in APP_IDS:
        app_path = f"$.apps.{app_id}"
        mount = apps.get(app_id)
        if not isinstance(mount, dict):
            add("MALFORMED_DOCUMENT", app_path, "expected object")
            continue

        enabled = mount.get("enabled")
        base_path_raw = mount.get("public_base_path")
        if not isinstance(enabled, bool):
            add("MALFORMED_DOCUMENT", f"{app_path}.enabled", "enabled must be boolean")
            continue
        if not isinstance(base_path_raw, str):
            add("MALFORMED_DOCUMENT", f"{app_path}.public_base_path", "public_base_path must be a string")
            continue

        try:
            base_path = normalize_public_base_path(base_path_raw)
        except ValueError as error:
            add("INVALID_PUBLIC_BASE_PATH", f"{app_path}.public_base_path", str(error))
            base_path = base_path_raw

        disconnected = mount.get("disconnected")
        if disconnected is not None and not isinstance(disconnected, dict):
            add("MALFORMED_DOCUMENT", f"{app_path}.disconnected", "expected object")
        elif isinstance(disconnected, dict):
            external = disconnected.get("external_origin")
            if not isinstance(external, dict):
                add("MALFORMED_DOCUMENT", f"{app_path}.disconnected.external_origin", "expected object")
            elif enabled:
                add(
                    "DISCONNECTED_CONFLICT",
                    f"{app_path}.disconnected",
                    "enabled apps on the shared origin must not declare an external disconnected origin",
                )
            else:
                _validate_origin(external, f"{app_path}.disconnected.external_origin", add)

        if enabled:
            if base_path == "":
                enabled_roots.append(app_id)
            enabled_paths[app_id] = base_path
        elif base_path != "":
            add(
                "DISABLED_APP_HAS_BASE_PATH",
                f"{app_path}.public_base_path",
                "disabled apps must use an empty public_base_path on the shared origin",
            )
        elif disconnected is None:
            add(
                "DISABLED_APP_MISSING_EXTERNAL",
                f"{app_path}.disconnected",
                "disabled apps should declare an external_origin for disconnected navigation",
            )

        oidc = mount.get("oidc")
        if not isinstance(oidc, dict):
            add("MALFORMED_DOCUMENT", f"{app_path}.oidc", "expected object")
            continue

        client_ref = oidc.get("client_ref")
        if not isinstance(client_ref, str) or not client_ref:
            add("MALFORMED_DOCUMENT", f"{app_path}.oidc.client_ref", "client_ref is required")
        else:
            previous_app = client_refs.get(client_ref)
            if previous_app is not None:
                add(
                    "DUPLICATE_OIDC_CLIENT",
                    f"{app_path}.oidc.client_ref",
                    f"OIDC client_ref is already used by {previous_app}",
                )
            else:
                client_refs[client_ref] = app_id

        redirect_path = oidc.get("redirect_path")
        try:
            normalized_redirect = normalize_app_relative_path(redirect_path)
        except (TypeError, ValueError) as error:
            add("INVALID_APP_PATH", f"{app_path}.oidc.redirect_path", str(error))
            normalized_redirect = None

        if enabled and normalized_redirect is not None:
            try:
                public_callback = join_public_path(base_path, normalized_redirect)
            except ValueError as error:
                add("INVALID_APP_PATH", f"{app_path}.oidc.redirect_path", str(error))
                public_callback = None
            if public_callback is not None:
                previous_callback = public_callbacks.get(public_callback)
                if previous_callback is not None:
                    add(
                        "DUPLICATE_PUBLIC_CALLBACK",
                        f"{app_path}.oidc.redirect_path",
                        f"public callback collides with {previous_callback}",
                    )
                else:
                    public_callbacks[public_callback] = app_id

        for field in ("post_logout_path",):
            value = oidc.get(field)
            if value is None:
                continue
            try:
                normalize_app_relative_path(value)
            except (TypeError, ValueError) as error:
                add("INVALID_APP_PATH", f"{app_path}.oidc.{field}", str(error))

        deep_links = mount.get("deep_link_paths")
        if deep_links is not None:
            if not isinstance(deep_links, list):
                add("MALFORMED_DOCUMENT", f"{app_path}.deep_link_paths", "expected array")
            else:
                seen: set[str] = set()
                for index, deep_link in enumerate(deep_links):
                    deep_path = f"{app_path}.deep_link_paths[{index}]"
                    try:
                        normalized = normalize_app_relative_path(deep_link)
                    except (TypeError, ValueError) as error:
                        add("INVALID_APP_PATH", deep_path, str(error))
                        continue
                    if normalized in seen:
                        add("DUPLICATE_DEEP_LINK", deep_path, "deep link paths must be unique")
                    seen.add(normalized)
                    if enabled:
                        for finding in validate_return_target(
                            public_origin,
                            base_path,
                            normalized,
                        ):
                            add(finding.code, deep_path, finding.message)

    if len(enabled_roots) > 1:
        add(
            "MULTIPLE_ROOT_MOUNTS",
            "$.apps",
            f"only one enabled app may use an empty public_base_path: {sorted(enabled_roots)}",
        )

    enabled_items = sorted(enabled_paths.items(), key=lambda item: item[1])
    for left_index, (left_app, left_path) in enumerate(enabled_items):
        for right_app, right_path in enabled_items[left_index + 1 :]:
            if paths_overlap(left_path, right_path):
                add(
                    "OVERLAPPING_BASE_PATH",
                    "$.apps",
                    f"{left_app} ({left_path!r}) overlaps {right_app} ({right_path!r}) without an exact segment boundary",
                )

    if landing_kind == "aithema_workspace":
        aithema = apps.get("aithema", {})
        if not aithema.get("enabled") or aithema.get("public_base_path", "unset") != "":
            add(
                "LANDING_MISMATCH",
                "$.landing",
                "aithema_workspace landing requires Aithema enabled at the shared origin root",
            )
    elif landing_kind == "connected_default_app" and landing_app is not None:
        default_mount = apps.get(landing_app, {})
        if not default_mount.get("enabled"):
            add(
                "LANDING_MISMATCH",
                "$.landing.app",
                "connected landing app must be enabled on the shared origin",
            )

    return findings


def paths_overlap(left: str, right: str) -> bool:
    try:
        left_path = normalize_public_base_path(left)
        right_path = normalize_public_base_path(right)
    except ValueError:
        return False
    if left_path == "" or right_path == "":
        return left_path == right_path
    return is_segment_prefix(left_path, right_path) or is_segment_prefix(right_path, left_path)


def _validate_origin(origin: Any, path: str, add) -> None:
    if not isinstance(origin, dict):
        add("MALFORMED_DOCUMENT", path, "expected object")
        return
    if origin.get("scheme") not in {"http", "https"}:
        add("MALFORMED_DOCUMENT", f"{path}.scheme", "scheme must be http or https")
    host = origin.get("host")
    if not isinstance(host, str) or not HOSTNAME.fullmatch(host):
        add("MALFORMED_DOCUMENT", f"{path}.host", "host must be scheme-less hostname with optional port")


def main(arguments: list[str]) -> int:
    if not arguments:
        print("usage: validate.py DOCUMENT.json [...]", file=sys.stderr)
        return 2
    failed = False
    for argument in arguments:
        path = Path(argument)
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"{path}: MALFORMED_DOCUMENT: {error}", file=sys.stderr)
            failed = True
            continue
        findings = validate_document(document)
        if findings:
            failed = True
            for finding in findings:
                print(f"{path}: {finding}", file=sys.stderr)
        else:
            print(f"{path}: valid")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
