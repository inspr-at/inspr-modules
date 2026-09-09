"""Source-backed unpublished control paths for the four native INSPR apps.

Patterns are copied from the public-base-path worktrees inspected for INSPR-387.
They are not guesses: each family is an actual registered route or route prefix.
The edge denies both the public mount and the unprefixed native path so a
root-mounted peer cannot receive another app's control plane by fall-through.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# Opaque path parameter (chi/axum `{id}` / `{hostRef}` / ...).
PARAM = None


@dataclass(frozen=True)
class DenyFamily:
    app_id: str
    name: str
    evidence: str
    segments: tuple[tuple[str | None, ...], ...]
    """Each inner tuple is one route. None is one path segment. A trailing '*'
    as the last element means 'this prefix and every subpath'."""


def _family(app_id: str, name: str, evidence: str, *routes: tuple[str | None, ...]) -> DenyFamily:
    return DenyFamily(app_id, name, evidence, routes)


# Paimos frozen supervisory-control classifier:
# paimos-worktrees/pai-972-public-base-path/backend/httpcontract/control_routes.go:89-111
_PAIMOS_CONTROL = (
    ("api", "projects", PARAM, "consumers", "v1", "streams"),
    ("api", "projects", PARAM, "consumers", "v1", "streams", PARAM, "claim"),
    ("api", "projects", PARAM, "consumers", "v1", "streams", PARAM, "attempts", PARAM, "execute"),
    ("api", "projects", PARAM, "consumers", "v1", "streams", PARAM, "attempts", PARAM, "complete"),
    ("api", "projects", PARAM, "consumers", "v1", "runtime-health"),
    ("api", "projects", PARAM, "message-deliveries", PARAM, "closed-target-recovery"),
    ("api", "agent-mode", "deliveries", PARAM, "control-capability-grants"),
    ("api", "agent-mode", "deliveries", PARAM, "control-commands"),
    ("api", "agent-mode", "control-capability-grants", PARAM),
    ("api", "agent-mode", "control-commands", PARAM),
    ("api", "runs", PARAM, "control-capability-leases"),
    ("api", "runs", PARAM, "input-requests"),
    ("api", "runs", PARAM, "control-commands"),
    ("api", "control-capability-leases", PARAM),
    ("api", "control-commands", PARAM),
    ("api", "agent-mode", "deliveries", PARAM, "external-stage-handoffs"),
    ("api", "agent-mode", "external-stage-handoffs", PARAM, "mint"),
    ("api", "agent-mode", "external-stage-handoffs", PARAM, "rotate"),
    ("api", "agent-mode", "external-stage-handoffs", PARAM, "revoke"),
    ("api", "external-stage", "handoffs", PARAM),
    ("api", "external-stage", "handoffs", PARAM, "accept"),
    ("api", "external-stage", "handoffs", PARAM, "reports"),
)

# Paimos private lifecycle authority:
# backend/handlers/lifecycle_intents.go:19-31 (mounted under /api)
_PAIMOS_LIFECYCLE = (
    ("api", "projects", PARAM, "lifecycle", "v1", "*"),
)

# Paimos admin debug + build-tag-gated dev login:
# backend/main.go:449-453 and 1150
_PAIMOS_DEBUG = (
    ("api", "import", "jira", "debug"),
    ("api", "auth", "dev-login"),
)

# Janus host-package / reconcile callbacks — go-envelope/main.go:810-813
# plus additional /internal managed-setup surfaces in the same tree.
_JANUS_INTERNAL = (
    ("internal", "*"),
    ("buildz",),
)

# Pharos machine plane that must not sit on the public customer HTTPS origin:
# crates/pharosd/src/routes.rs:170, 196-247
_PHAROS_MACHINE = (
    ("metrics",),
    ("register",),
    ("report",),
    ("agent", "*"),
    ("internal", "*"),
)

# Aithema demo session is loopback-gated in-app (workspace/server.js:158-176).
# Public packaging still must not publish it.
_AITHEMA_DEMO = (("session", "demo"),)

DENY_FAMILIES: tuple[DenyFamily, ...] = (
    _family("paimos", "supervisory-control", "httpcontract/control_routes.go", *_PAIMOS_CONTROL),
    _family("paimos", "lifecycle-authority", "handlers/lifecycle_intents.go", *_PAIMOS_LIFECYCLE),
    _family("paimos", "debug-and-dev-login", "backend/main.go", *_PAIMOS_DEBUG),
    _family("janus", "internal-control", "go-envelope/main.go routeSpecs", *_JANUS_INTERNAL),
    _family("pharos", "machine-and-internal", "crates/pharosd/src/routes.rs", *_PHAROS_MACHINE),
    _family("aithema", "demo-session", "workspace/server.js", *_AITHEMA_DEMO),
)

# SSE paths that MUST remain published (Paimos only). Never put these in DENY_FAMILIES.
# backend/main.go:654 (changes), 546 (agent-mode events), 908 (intake stream)
PAIMOS_SSE_APP_PATHS = (
    "/api/changes",
    "/api/agent-mode/deliveries/events",
    "/api/intake/sessions/{id}/stream",
)

DEFAULT_CONNECTED_PATHS = {
    "aithema": "/aithema",
    "paimos": "/paimos",
    "pharos": "/pharos",
    "janus": "/janus",
}

_SEGMENT_RE = re.compile(r"^[A-Za-z0-9._~!$&'()*+,;=:@%-]+$")


def route_regex(public_base_path: str, segments: tuple[str | None, ...]) -> str:
    """Return a Traefik PathRegexp body (no surrounding slashes/backticks)."""
    if not segments:
        raise ValueError("deny route must have segments")
    parts: list[str] = []
    prefix_star = segments[-1] == "*"
    body = segments[:-1] if prefix_star else segments
    for segment in body:
        if segment is PARAM:
            parts.append("[^/]+")
        elif segment == "*":
            raise ValueError("'*' is only allowed as the last deny segment")
        elif not isinstance(segment, str) or not _SEGMENT_RE.fullmatch(segment):
            raise ValueError(f"refuse unsound deny segment: {segment!r}")
        else:
            parts.append(segment)
    path = "/" + "/".join(parts)
    if public_base_path:
        path = public_base_path + path
    if prefix_star:
        return "^" + path + "(?:/.*)?$"
    return "^" + path + "$"


def native_and_public_regexes(public_base_path: str, segments: tuple[str | None, ...]) -> list[str]:
    regexes = [route_regex("", segments)]
    if public_base_path:
        regexes.append(route_regex(public_base_path, segments))
    return regexes


def deny_regexes_for_app(app_id: str, public_base_path: str) -> list[str]:
    regexes: list[str] = []
    seen: set[str] = set()
    for family in DENY_FAMILIES:
        if family.app_id != app_id:
            continue
        for segments in family.segments:
            for regex in native_and_public_regexes(public_base_path, segments):
                if regex not in seen:
                    seen.add(regex)
                    regexes.append(regex)
    return regexes


def sse_regexes(public_base_path: str) -> list[str]:
    return [
        route_regex(public_base_path, ("api", "changes")),
        route_regex(public_base_path, ("api", "agent-mode", "deliveries", "events")),
        route_regex(public_base_path, ("api", "intake", "sessions", PARAM, "stream")),
    ]


def family_summaries(app_id: str) -> list[str]:
    return [f"{family.name} ({family.evidence})" for family in DENY_FAMILIES if family.app_id == app_id]
