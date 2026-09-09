"""Compile an inspr.routing contract plus deployment inputs into Traefik 3.7.13 config."""

from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit

CONTRACT_ROOT = Path(__file__).resolve().parents[3] / "contracts" / "routing"
sys.path.insert(0, str(CONTRACT_ROOT))
from validate import (  # noqa: E402
    APP_IDS,
    Finding,
    join_public_path,
    public_url,
    validate_document,
)

from .deny import (
    DEFAULT_CONNECTED_PATHS,
    PAIMOS_SSE_APP_PATHS,
    deny_regexes_for_app,
    family_summaries,
)
from .deployment import (
    EXTERNAL_MODE,
    MANAGED_MODE,
    PINNED_TRAEFIK_SYNTAX,
    PINNED_TRAEFIK_VERSION,
    PINNED_TRAEFIK_RELEASE,
    PINNED_TRAEFIK_OCI_IMAGE,
    PINNED_TRAEFIK_OCI_INDEX_DIGEST,
    PINNED_TRAEFIK_OCI_LINUX_AMD64_DIGEST,
    DeploymentInput,
    parse_deployment,
    is_loopback_host,
    is_private_or_loopback_host,
)
from .yaml_emit import emit_yaml


DENY_PRIORITY = 10000
LANDING_PRIORITY = 50
PREFIX_PRIORITY_BASE = 100
ROOT_PRIORITY = 10
DROP_IDENTITY_HEADERS = {
    "X-Forwarded-User": "",
    "X-Remote-User": "",
    "Remote-User": "",
}
FORBIDDEN_GENERATED = (
    "stripPrefix:",
    "stripprefix:",
    "Access-Control-Allow-Origin",
    "buffering:",
    "insecureSkipVerify",
)


@dataclass
class GenerateResult:
    findings: list[Finding] = field(default_factory=list)
    dynamic: dict[str, Any] = field(default_factory=dict)
    static: dict[str, Any] = field(default_factory=dict)
    dynamic_yaml: str = ""
    static_yaml: str = ""
    report: dict[str, Any] = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return not self.findings


def compile_edge(contract: Any, deployment_document: Any, *, dynamic_filename: str = "dynamic.yml") -> GenerateResult:
    findings = list(validate_document(contract))
    deployment, deploy_findings = parse_deployment(deployment_document)
    findings.extend(deploy_findings)
    if findings or deployment is None:
        return GenerateResult(findings=findings)
    findings.extend(_topology_findings(contract, deployment))
    if findings:
        return GenerateResult(findings=findings)

    public_origin = contract["public_origin"]
    host_rule = _host_rule(public_origin["host"])
    entry = deployment.entrypoint_name
    namespace = deployment.resource_namespace

    def resource(suffix: str) -> str:
        return f"{namespace}-{suffix}"

    diagnostic_headers = (contract.get("edge") or {}).get("optional_diagnostic_headers") or []
    diagnostic_prefix = "X-Forwarded-Prefix" in diagnostic_headers
    tls_public = not deployment.loopback_http_fixture

    middlewares: dict[str, Any] = {
        resource("deny-unpublished"): {
            "ipAllowList": {"sourceRange": ["255.255.255.255/32"]},
        },
        resource("drop-forwarded-identity"): {
            "headers": {"customRequestHeaders": dict(DROP_IDENTITY_HEADERS)},
        },
    }
    routers: dict[str, Any] = {}
    services: dict[str, Any] = {
        resource("deny-unpublished"): {
            "loadBalancer": {
                "passHostHeader": False,
                "servers": [{"url": "http://127.0.0.1:1"}],
            }
        }
    }
    transports: dict[str, Any] = {}

    enabled = {app_id: contract["apps"][app_id] for app_id in APP_IDS if contract["apps"][app_id]["enabled"]}
    disabled = {app_id: contract["apps"][app_id] for app_id in APP_IDS if not contract["apps"][app_id]["enabled"]}
    enabled_paths = {app_id: mount["public_base_path"] for app_id, mount in enabled.items()}

    for app_id, mount in enabled.items():
        upstream = deployment.upstreams[app_id]
        base = mount["public_base_path"]
        transport_name = resource(f"stream-{app_id}")
        transports[transport_name] = _stream_transport(upstream.ca_file)
        services[resource(f"upstream-{app_id}")] = {
            "loadBalancer": {
                "passHostHeader": True,
                "servers": [{"url": upstream.origin}],
                "serversTransport": transport_name,
            }
        }
        chain = [resource("drop-forwarded-identity")]
        if diagnostic_prefix:
            header_name = resource(f"prefix-{app_id}")
            middlewares[header_name] = {
                "headers": {
                    "customRequestHeaders": {
                        "X-Forwarded-Prefix": base,
                    }
                }
            }
            chain.append(header_name)
        chain_name = resource(f"app-{app_id}")
        middlewares[chain_name] = {"chain": {"middlewares": chain}}
        rule = _app_rule(host_rule, base)
        priority = ROOT_PRIORITY if base == "" else PREFIX_PRIORITY_BASE + len(base)
        routers[resource(f"app-{app_id}")] = _router(
            rule=rule,
            entry=entry,
            service=resource(f"upstream-{app_id}"),
            middlewares=[chain_name],
            priority=priority,
            tls=tls_public,
            certificate_resolver=deployment.certificate_resolver,
        )
        deny_rule = _deny_rule(host_rule, deny_regexes_for_app(app_id, base))
        if deny_rule:
            routers[resource(f"deny-{app_id}")] = _router(
                rule=deny_rule,
                entry=entry,
                service=resource("deny-unpublished"),
                middlewares=[resource("deny-unpublished")],
                priority=DENY_PRIORITY,
                tls=tls_public,
                certificate_resolver=deployment.certificate_resolver,
            )

    occupied = set(enabled_paths.values())
    reserved: list[str] = []
    for app_id, mount in disabled.items():
        default_path = DEFAULT_CONNECTED_PATHS[app_id]
        if default_path not in occupied and default_path != "":
            reserved.append(default_path)
    if reserved:
        reserved_regexes = [f"^{_escape_path(path)}(?:/.*)?$" for path in sorted(reserved)]
        routers[resource("deny-disabled-vocabulary")] = _router(
            rule=_deny_rule(host_rule, reserved_regexes),
            entry=entry,
            service=resource("deny-unpublished"),
            middlewares=[resource("deny-unpublished")],
            priority=DENY_PRIORITY - 1,
            tls=tls_public,
            certificate_resolver=deployment.certificate_resolver,
        )

    landing = contract["landing"]
    root_app = next((app_id for app_id, path in enabled_paths.items() if path == ""), None)
    if root_app is None:
        landing_app = landing["app"] if landing["kind"] == "connected_default_app" else None
        if landing["kind"] == "aithema_workspace":
            landing_app = "aithema"
        if landing_app not in enabled:
            return GenerateResult(
                findings=[Finding("LANDING_MISMATCH", "$.landing", "landing app is not enabled")]
            )
        landing_path = enabled_paths[landing_app] or "/"
        target = f"{public_origin['scheme']}://{public_origin['host']}{landing_path}"
        middlewares[resource("landing-redirect")] = {
            "redirectRegex": {
                "regex": "^https?://[^/]+/?$",
                "replacement": target,
                "permanent": False,
            }
        }
        routers[resource("landing")] = _router(
            rule=f"{host_rule} && Path(`/`)",
            entry=entry,
            service=resource("deny-unpublished"),
            middlewares=[resource("landing-redirect")],
            priority=LANDING_PRIORITY,
            tls=tls_public,
            certificate_resolver=deployment.certificate_resolver,
        )

    dynamic: dict[str, Any] = {
        "http": {
            "middlewares": dict(sorted(middlewares.items())),
            "routers": dict(sorted(routers.items())),
            "services": dict(sorted(services.items())),
            "serversTransports": dict(sorted(transports.items())),
        }
    }
    if tls_public and deployment.mode == MANAGED_MODE:
        dynamic["tls"] = {
            "certificates": [
                {"certFile": deployment.cert_file, "keyFile": deployment.key_file},
            ]
        }

    static = {
        "global": {
            "checkNewVersion": False,
            "sendAnonymousUsage": False,
        },
        "log": {"level": "ERROR"},
        "entryPoints": {
            deployment.entrypoint_name: {
                "address": deployment.entrypoint_address,
                "forwardedHeaders": {"insecure": False},
                "transport": {
                    "respondingTimeouts": {
                        "readTimeout": "0s",
                        "writeTimeout": "0s",
                        "idleTimeout": "180s",
                    }
                },
            }
        },
        "providers": {
            "file": {
                "filename": dynamic_filename,
                "watch": False,
            }
        },
    } if deployment.mode == MANAGED_MODE else {}

    header = (
        f"INSPR routing-edge Traefik dynamic configuration\n"
        f"Pinned syntax: Traefik {PINNED_TRAEFIK_VERSION} {PINNED_TRAEFIK_SYNTAX}\n"
        "Prefix-preserving: prefixes are not stripped; no HTML rewrite; no identity injection.\n"
        "Schema validity is not live SSO proof. Upstream TLS/SSO are not attested."
    )
    if deployment.mode == EXTERNAL_MODE:
        header += (
            "\nExternal file-provider fragment only: the consumer owns the entrypoint,"
            " certificate resolver, provider directory, TLS and process lifecycle."
            f"\nResource namespace: {namespace}. Install only this fragment; collisions are consumer-owned."
        )
    static_header = (
        f"INSPR routing-edge Traefik static configuration\n"
        f"Pinned syntax: Traefik {PINNED_TRAEFIK_VERSION}. Dashboard/API omitted (disabled).\n"
        "Do not enable insecure forwardedHeaders or the dashboard on this entrypoint."
    )
    dynamic_yaml = emit_yaml(dynamic, header)
    static_yaml = emit_yaml(static, static_header) if static else ""
    _assert_safe_generated(dynamic_yaml)
    _assert_safe_generated(static_yaml)

    report = _wiring_report(contract, deployment, enabled_paths, tls_public, reserved)
    return GenerateResult(
        findings=[],
        dynamic=dynamic,
        static=static,
        dynamic_yaml=dynamic_yaml,
        static_yaml=static_yaml,
        report=report,
    )


def write_outputs(result: GenerateResult, output_dir: Path) -> None:
    if not result.ok:
        raise ValueError("refusing to write failed compilation")
    output_dir.mkdir(parents=True, exist_ok=True)
    dynamic_path = output_dir / "dynamic.yml"
    static_path = output_dir / "static.yml"
    report_path = output_dir / "wiring-report.json"
    if not result.static:
        if dynamic_path.exists() and not dynamic_path.read_text(encoding="utf-8").startswith(
            "# INSPR routing-edge Traefik dynamic configuration\n"
        ):
            raise ValueError(
                "refusing to overwrite dynamic.yml not owned by the INSPR routing-edge compiler"
            )
        if static_path.exists():
            existing = static_path.read_text(encoding="utf-8")
            if not existing.startswith("# INSPR routing-edge Traefik static configuration\n"):
                raise ValueError(
                    "refusing to remove static.yml not owned by the INSPR routing-edge compiler"
                )
        if report_path.exists():
            try:
                existing_report = json.loads(report_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as error:
                raise ValueError(
                    "refusing to overwrite wiring-report.json not owned by the INSPR routing-edge compiler"
                ) from error
            report_markers = {"contract_version", "traefik", "apps", "operator_secrets_exported"}
            if not isinstance(existing_report, dict) or not report_markers <= set(existing_report):
                raise ValueError(
                    "refusing to overwrite wiring-report.json not owned by the INSPR routing-edge compiler"
                )
        if static_path.exists():
            static_path.unlink()
        dynamic_path.write_text(result.dynamic_yaml, encoding="utf-8")
        report_path.write_text(
            json.dumps(result.report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return
    dynamic_path.write_text(result.dynamic_yaml, encoding="utf-8")
    # Re-emit static with an absolute dynamic filename so Traefik can start.
    static = dict(result.static)
    providers = dict(static["providers"])
    file_provider = dict(providers["file"])
    file_provider["filename"] = str((output_dir / "dynamic.yml").resolve())
    providers["file"] = file_provider
    static["providers"] = providers
    static_yaml = emit_yaml(
        static,
        f"INSPR routing-edge Traefik static configuration\n"
        f"Pinned syntax: Traefik {PINNED_TRAEFIK_VERSION}. Dashboard/API omitted (disabled).",
    )
    static_path.write_text(static_yaml, encoding="utf-8")
    (output_dir / "wiring-report.json").write_text(
        json.dumps(result.report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def _topology_findings(contract: Any, deployment: DeploymentInput) -> list[Finding]:
    findings: list[Finding] = []
    origin = contract["public_origin"]
    origin_host = origin["host"].split(":")[0]
    origin_netloc = origin["host"]

    if deployment.loopback_http_fixture:
        if origin["scheme"] != "http":
            findings.append(Finding("INSECURE_TOPOLOGY", "$.public_origin.scheme", "loopback HTTP fixture requires http"))
        if not is_loopback_host(origin_host):
            findings.append(Finding("INSECURE_TOPOLOGY", "$.public_origin.host", "loopback HTTP fixture requires a loopback host"))
    else:
        if origin["scheme"] != "https":
            findings.append(Finding("INSECURE_TOPOLOGY", "$.public_origin.scheme", "public operation requires https"))
        if is_loopback_host(origin_host) is False and origin["scheme"] == "http":
            findings.append(Finding("INSECURE_TOPOLOGY", "$.public_origin.host", "public HTTP is forbidden"))

    for app_id in APP_IDS:
        mount = contract["apps"][app_id]
        has_upstream = app_id in deployment.upstreams
        if mount["enabled"] and not has_upstream:
            findings.append(Finding("MISSING_UPSTREAM", f"$.upstreams.{app_id}", "enabled apps require an explicit upstream origin"))
        if not mount["enabled"] and has_upstream:
            findings.append(Finding("UNSUPPORTED_WIRING", f"$.upstreams.{app_id}", "disabled apps must not receive an upstream (do not proxy a dead prefix)"))
        if not mount["enabled"]:
            continue
        if not has_upstream:
            continue
        upstream = deployment.upstreams[app_id]
        if _same_public_origin(origin["scheme"], origin_netloc, upstream):
            findings.append(
                Finding(
                    "UNSUPPORTED_WIRING",
                    f"$.upstreams.{app_id}.url",
                    "upstream must be an explicit server distinct from the public origin",
                )
            )
        if upstream.scheme == "http" and not is_private_or_loopback_host(upstream.host):
            findings.append(
                Finding(
                    "INSECURE_TOPOLOGY",
                    f"$.upstreams.{app_id}.url",
                    "http upstreams are only allowed on loopback or private addresses",
                )
            )
        if deployment.loopback_http_fixture and not is_loopback_host(upstream.host):
            findings.append(
                Finding(
                    "INSECURE_TOPOLOGY",
                    f"$.upstreams.{app_id}.url",
                    "loopback HTTP fixture mode requires loopback upstreams",
                )
            )
    return findings


def _same_public_origin(scheme: str, origin_netloc: str, upstream) -> bool:
    public = urlsplit(f"{scheme}://{origin_netloc}")
    if (upstream.scheme, upstream.host) != (public.scheme, public.hostname):
        return False
    public_port = public.port or (443 if scheme == "https" else 80)
    upstream_port = upstream.port or (443 if upstream.scheme == "https" else 80)
    return public_port == upstream_port


def _host_rule(host: str) -> str:
    hostname = host
    if ":" in host and not host.startswith("["):
        hostname = host.rsplit(":", 1)[0]
    if "`" in hostname or "{" in hostname or "}" in hostname:
        raise ValueError("host contains characters that cannot appear in a Traefik Host rule")
    return f"Host(`{hostname}`)"


def _app_rule(host_rule: str, base: str) -> str:
    if base == "":
        return f"{host_rule} && PathRegexp(`^/.*$`)"
    return f"{host_rule} && PathRegexp(`^{_escape_path(base)}(?:/.*)?$`)"


def _escape_path(path: str) -> str:
    return re.escape(path)


def _deny_rule(host_rule: str, regexes: list[str]) -> str:
    if not regexes:
        return ""
    bodies = []
    for regex in regexes:
        body = regex
        if body.startswith("^"):
            body = body[1:]
        if body.endswith("$"):
            body = body[:-1]
        bodies.append(f"(?:{body})")
    return f"{host_rule} && PathRegexp(`^(?:{'|'.join(bodies)})$`)"


def _router(
    *,
    rule: str,
    entry: str,
    service: str,
    middlewares: list[str],
    priority: int,
    tls: bool,
    certificate_resolver: str | None,
) -> dict[str, Any]:
    router = {
        "rule": rule,
        "entryPoints": [entry],
        "service": service,
        "middlewares": middlewares,
        "priority": priority,
    }
    if tls:
        router["tls"] = (
            {"certResolver": certificate_resolver}
            if certificate_resolver is not None
            else {}
        )
    return router


def _stream_transport(ca_file: str | None) -> dict[str, Any]:
    transport: dict[str, Any] = {
        "forwardingTimeouts": {
            "dialTimeout": "30s",
            "responseHeaderTimeout": "0s",
            "idleConnTimeout": "0s",
        }
    }
    if ca_file:
        transport["rootCAs"] = [ca_file]
    return transport


def _assert_safe_generated(text: str) -> None:
    for token in FORBIDDEN_GENERATED:
        if token in text and token != 'X-Forwarded-User: ""':
            if token.startswith("X-Forwarded-User") and 'X-Forwarded-User: ""' in text:
                continue
            if token == 'X-Forwarded-User: "' and 'X-Forwarded-User: ""' in text:
                continue
            raise ValueError(f"generated configuration contains forbidden token {token!r}")
    if "stripPrefix:" in text or "StripPrefix:" in text:
        raise ValueError("generated configuration must not strip prefixes")
    if "Access-Control-Allow-Origin" in text:
        raise ValueError("generated configuration must not set CORS")
    if "buffering:" in text:
        raise ValueError("generated configuration must not enable response buffering")
    if "insecureSkipVerify" in text:
        raise ValueError("generated configuration must not skip upstream TLS verify")


def _wiring_report(
    contract: Any,
    deployment: DeploymentInput,
    enabled_paths: dict[str, str],
    tls_public: bool,
    reserved: list[str],
) -> dict[str, Any]:
    origin = contract["public_origin"]
    apps: dict[str, Any] = {}
    for app_id in APP_IDS:
        mount = contract["apps"][app_id]
        enabled = bool(mount["enabled"])
        entry: dict[str, Any] = {
            "enabled": enabled,
            "public_base_path": mount["public_base_path"] if enabled else "",
            "oidc_redirect_path": mount["oidc"]["redirect_path"],
            "unpublished_control_families": family_summaries(app_id),
        }
        if enabled:
            upstream = deployment.upstreams[app_id]
            entry["upstream_origin"] = upstream.origin
            entry["oidc_redirect_url"] = public_url(origin, mount["public_base_path"], mount["oidc"]["redirect_path"])
            entry["join_examples"] = {
                "callback": join_public_path(mount["public_base_path"], mount["oidc"]["redirect_path"]),
            }
            if app_id == "paimos":
                sse_paths = []
                for path in PAIMOS_SSE_APP_PATHS:
                    endpoint = "/api/intake/sessions/demo/stream" if "{id}" in path else path
                    sse_paths.append(join_public_path(mount["public_base_path"], endpoint))
                entry["sse"] = {
                    "mode": "stream-not-buffer",
                    "paths": sse_paths,
                    "forwardingTimeouts": "responseHeaderTimeout=0s, idleConnTimeout=0s",
                }
            else:
                entry["sse"] = {"mode": "none-at-app"}
        else:
            disconnected = mount.get("disconnected") or {}
            external = disconnected.get("external_origin")
            if isinstance(external, dict):
                entry["disconnected_external_origin"] = f"{external['scheme']}://{external['host']}"
            entry["proxied"] = False
        apps[app_id] = entry
    report = {
        "contract_version": contract["contract_version"],
        "authority_disclaimer": contract["authority_disclaimer"],
        "traefik": {
            "version": PINNED_TRAEFIK_VERSION,
            "syntax": PINNED_TRAEFIK_SYNTAX,
            "release": PINNED_TRAEFIK_RELEASE,
            "provider": "file",
            "untested_versions_claimed": False,
            "process_proof_oci": {
                "image": PINNED_TRAEFIK_OCI_IMAGE,
                "index_digest": PINNED_TRAEFIK_OCI_INDEX_DIGEST,
                "linux_amd64_digest": PINNED_TRAEFIK_OCI_LINUX_AMD64_DIGEST,
            },
        },
        "public_origin": {"scheme": origin["scheme"], "host": origin["host"]},
        "landing": contract["landing"],
        "tls_public": tls_public,
        "loopback_http_fixture": deployment.loopback_http_fixture,
        "path_strategy": "prefix_preserving",
        "strip_prefix": False,
        "html_response_rewrite": False,
        "iframe_gateway": False,
        "permissive_cors": False,
        "forwarded_identity_trust": False,
        "identity_header_injection": False,
        "shared_session_fallback": False,
        "dynamic_request_upstream_selection": False,
        "sso_verified": False,
        "upstream_tls_attested": False,
        "pass_host_header": True,
        "reserved_disabled_vocabulary": reserved,
        "apps": apps,
        "operator_secrets_exported": False,
    }
    if deployment.mode == EXTERNAL_MODE:
        report.update(
            {
                "deployment_mode": EXTERNAL_MODE,
                "static_listener_generated": False,
                "resource_namespace": deployment.resource_namespace,
                "consumer_runtime_prerequisites": {
                    "entrypoint": deployment.entrypoint_name,
                    "certificate_resolver": deployment.certificate_resolver,
                    "file_provider_install": "install dynamic.yml as one uniquely named provider fragment",
                    "upstream_ca_visibility": "every ca_file path must be readable by the existing Traefik process",
                    "traefik_version": PINNED_TRAEFIK_VERSION,
                },
                "public_tls_runtime_verified": False,
            }
        )
    return report
