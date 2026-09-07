# SPDX-License-Identifier: AGPL-3.0-only
"""Closed, versioned profile and evidence contract for inspr readiness."""

from __future__ import annotations

import hashlib
import json
import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping

from . import CONTRACT_VERSION

MAX_PROFILE_BYTES = 65536
MAX_PATH_BYTES = 4096
MAX_OUTPUT_BYTES = 65536
MAX_STRING = 128
MAX_IDENTITY = 64
MAX_ACCOUNT_KEY = 128
MAX_CHECKS = 32
MAX_CAPABILITIES = 16
MAX_TOOLS = 16
MAX_TTL_SECONDS = 3600
MIN_TTL_SECONDS = 30
SUBPROCESS_TIMEOUT_SECONDS = 20
ACCOUNT_PROBE_TIMEOUT_SECONDS = 5
ACCOUNT_PROBE_OUTPUT_BYTES = 1024
CACHE_SCHEMA = "inspr.readiness.cache.v1"

DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
IDENTITY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
ACCOUNT_KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
TOOL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$")
REVISION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")

HOST_KINDS = ("nixos-home-manager", "macos-home-manager")
HARNESSES = ("claude", "codex")
EFFORTS = ("low", "medium", "high", "xhigh", "max")
WORKSPACE_MODES = ("exclusive", "shared")
OVERALL_STATUSES = ("ready", "needs_setup", "unavailable")
CHECK_STATUSES = ("pass", "fail", "warn", "unknown", "unsupported", "stale")
BLOCKING_UNKNOWN = frozenset({"unknown", "unsupported", "stale"})

BUILT_IN_CHECKS = (
    "host_kind",
    "activated_generation",
    "doctrine_loader",
    "workspace_isolation",
    "tool_prerequisites",
    "paimos_runtime_doctor",
    "paimos_account",
    "dispatch_profile",
)

REQUESTED_CAPABILITIES = (
    "runtime_ready",
    "named_account",
    "exclusive_workspace",
    "dispatch_profile",
)

ACCOUNT_LABELS = (
    "chatgpt",
    "api_key",
    "claude_ai_max",
    "claude_ai_pro",
    "claude_ai_team",
    "claude_ai_enterprise",
    "console",
)

NEXT_ACTIONS = (
    "none",
    "adopt_nix_home_manager",
    "activate_home_manager",
    "activate_nixos_generation",
    "repair_doctrine_loader",
    "select_declared_workspace",
    "install_declared_tools",
    "configure_paimos_instance",
    "run_paimos_runtime_setup",
    "verify_named_account",
    "install_missing_integration",
)

DOCTOR_LAYER_NAMES = frozenset(
    {
        "cli_auth",
        "server_identity",
        "canonical_agents",
        "dispatch_profiles",
        "targets",
        "private_paths",
        "daemon_service",
        "daemon_generation",
        "socket_lock",
        "journal",
        "reporter_lease",
        "stale_generations",
        "workspace_ownership",
        "consumers",
        "browser_intents",
        "primary_inbox",
        "repair_budget",
    }
)
DOCTOR_STATES = frozenset({"known", "unknown", "action_required", "repaired", "preserved"})
DOCTOR_CODE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_]{0,63}$")

PROFILE_TOP = frozenset(
    {
        "contract_version",
        "profile_id",
        "identities",
        "expected",
        "requested_capabilities",
        "checks",
        "inputs",
        "observation_ttl_seconds",
    }
)
IDENTITY_KEYS = frozenset(
    {"execution_host", "runtime", "project", "account", "harness", "workspace"}
)
EXPECTED_KEYS = frozenset(
    {
        "host_kind",
        "home_manager_generation_digest",
        "nix_system_generation_digest",
        "doctrine_kernel_digest",
        "config_revision",
        "flake_lock_digest",
        "paimos_instance",
        "paimos_deployment",
        "paimos_project_key",
        "account_label",
        "account_key",
        "harness",
        "model",
        "effort",
        "workspace_mode",
        "workspace_identity_digest",
        "tools",
    }
)
INPUT_KEYS = frozenset(
    {
        "workspace_root",
        "doctrine_kernel",
        "doctrine_loader",
        "flake_lock",
        "cache_dir",
    }
)
CHECK_GROUP_KEYS = frozenset({"required", "optional"})
REDACT_HINTS = (
    "http://",
    "https://",
    "@",
    "/Users/",
    "/home/",
    "/nix/store/",
    "/run/",
    ".ssh/",
    "BEGIN ",
)


class ProfileError(ValueError):
    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


def digest_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def digest_text(text: str) -> str:
    return digest_bytes(text.encode("utf-8"))


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def parse_now(value: str | None) -> datetime:
    if not value:
        return utcnow()
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ProfileError("invalid_observation_time") from exc
    if parsed.tzinfo is None:
        raise ProfileError("invalid_observation_time")
    return parsed.astimezone(timezone.utc).replace(microsecond=0)


def require_mapping(value: Any, reason: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ProfileError(reason)
    for key in value:
        if not isinstance(key, str):
            raise ProfileError(reason)
    return value


def require_identity(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not IDENTITY_RE.fullmatch(value):
        raise ProfileError(f"invalid_{field}")
    return value


def require_digest(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not DIGEST_RE.fullmatch(value):
        raise ProfileError(f"invalid_{field}")
    return value


def require_safe_path(value: Any, *, field: str) -> str:
    if not isinstance(value, str) or not value or len(value.encode("utf-8")) > MAX_PATH_BYTES:
        raise ProfileError(f"unsafe_{field}")
    if not value.startswith("/") or any(ch in value for ch in "\x00\r\n"):
        raise ProfileError(f"unsafe_{field}")
    if value != os.path.normpath(value):
        raise ProfileError(f"unsafe_{field}")
    parts = [part for part in value.split("/") if part]
    if any(part in (".", "..") for part in parts):
        raise ProfileError(f"unsafe_{field}")
    return value


def closed_reason(reason: str) -> str:
    if not isinstance(reason, str) or not DOCTOR_CODE_RE.fullmatch(reason):
        return "internal_error"
    return reason


def redacted(text: str) -> bool:
    lowered = text.lower()
    if any(hint.lower() in text or hint.lower() in lowered for hint in REDACT_HINTS):
        return True
    if "/" in text and len(text) > 8:
        return True
    return False


def sanitize_exported_reason(reason: str) -> str:
    reason = closed_reason(reason)
    if redacted(reason):
        return "redacted"
    return reason


@dataclass(frozen=True)
class Profile:
    profile_id: str
    identities: dict[str, str]
    expected: dict[str, Any]
    requested_capabilities: tuple[str, ...]
    required_checks: tuple[str, ...]
    optional_checks: tuple[str, ...]
    inputs: dict[str, str]
    observation_ttl_seconds: int
    source_bytes: bytes

    @property
    def digest(self) -> str:
        return digest_bytes(self.source_bytes)

    def requires(self, check_id: str) -> bool:
        return check_id in self.required_checks

    def selected(self, check_id: str) -> bool:
        return check_id in self.required_checks or check_id in self.optional_checks


@dataclass
class CheckResult:
    id: str
    status: str
    reason: str
    digest: str | None = None

    def as_dict(self) -> dict[str, Any]:
        out: dict[str, Any] = {
            "id": self.id,
            "status": self.status,
            "reason": sanitize_exported_reason(self.reason),
        }
        if self.digest:
            out["digest"] = self.digest
        return out


@dataclass
class Evidence:
    status: str
    observed_at: datetime
    expires_at: datetime
    profile_id: str
    profile_digest: str
    context: dict[str, str]
    expected_revisions: dict[str, str]
    checks: list[CheckResult] = field(default_factory=list)
    next_action: str = "none"

    def as_dict(self) -> dict[str, Any]:
        return {
            "contract_version": CONTRACT_VERSION,
            "status": self.status,
            "observed_at": _fmt_time(self.observed_at),
            "expires_at": _fmt_time(self.expires_at),
            "profile_id": self.profile_id,
            "profile_digest": self.profile_digest,
            "context": dict(self.context),
            "expected_revisions": dict(self.expected_revisions),
            "checks": [item.as_dict() for item in self.checks],
            "next_action": self.next_action,
        }


def _fmt_time(value: datetime) -> str:
    return value.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def load_profile_bytes(raw: bytes) -> Profile:
    if len(raw) == 0 or len(raw) > MAX_PROFILE_BYTES:
        raise ProfileError("profile_size")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ProfileError("profile_encoding") from exc
    try:
        payload = json.loads(text)
    except json.JSONDecodeError as exc:
        raise ProfileError("profile_json") from exc
    return parse_profile(payload, source_bytes=raw)


def parse_profile(payload: Any, *, source_bytes: bytes | None = None) -> Profile:
    data = require_mapping(payload, "profile_json")
    unknown = set(data) - PROFILE_TOP
    if unknown:
        raise ProfileError("unknown_field")
    if data.get("contract_version") != CONTRACT_VERSION:
        raise ProfileError("unsupported_contract")
    profile_id = require_identity(data.get("profile_id"), field="profile_id")

    identities_raw = require_mapping(data.get("identities"), "invalid_identities")
    if set(identities_raw) != IDENTITY_KEYS:
        raise ProfileError("invalid_identities")
    identities = {
        key: require_identity(identities_raw[key], field=f"identity_{key}")
        for key in sorted(IDENTITY_KEYS)
    }

    expected_raw = require_mapping(data.get("expected"), "invalid_expected")
    if set(expected_raw) - EXPECTED_KEYS:
        raise ProfileError("unknown_field")
    expected = _parse_expected(expected_raw)

    capabilities = _parse_closed_list(
        data.get("requested_capabilities", []),
        allowed=REQUESTED_CAPABILITIES,
        reason="invalid_capability",
        limit=MAX_CAPABILITIES,
    )
    checks_raw = require_mapping(data.get("checks"), "invalid_checks")
    if set(checks_raw) - CHECK_GROUP_KEYS:
        raise ProfileError("unknown_field")
    required = _parse_closed_list(
        checks_raw.get("required", []),
        allowed=BUILT_IN_CHECKS,
        reason="unknown_check",
        limit=MAX_CHECKS,
    )
    optional = _parse_closed_list(
        checks_raw.get("optional", []),
        allowed=BUILT_IN_CHECKS,
        reason="unknown_check",
        limit=MAX_CHECKS,
    )
    if set(required) & set(optional):
        raise ProfileError("overlapping_checks")
    if not required:
        raise ProfileError("empty_required_checks")

    inputs_raw = require_mapping(data.get("inputs", {}), "invalid_inputs")
    if set(inputs_raw) - INPUT_KEYS:
        raise ProfileError("unknown_field")
    inputs = {
        key: require_safe_path(value, field=f"input_{key}")
        for key, value in inputs_raw.items()
        if value not in (None, "")
    }

    ttl = data.get("observation_ttl_seconds", 300)
    if not isinstance(ttl, int) or isinstance(ttl, bool) or ttl < MIN_TTL_SECONDS or ttl > MAX_TTL_SECONDS:
        raise ProfileError("invalid_ttl")

    _require_check_inputs(required, expected, inputs)
    encoded = source_bytes if source_bytes is not None else json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return Profile(
        profile_id=profile_id,
        identities=identities,
        expected=expected,
        requested_capabilities=capabilities,
        required_checks=required,
        optional_checks=optional,
        inputs=inputs,
        observation_ttl_seconds=ttl,
        source_bytes=encoded,
    )


def _parse_expected(raw: Mapping[str, Any]) -> dict[str, Any]:
    expected: dict[str, Any] = {}
    if "host_kind" in raw:
        if raw["host_kind"] not in HOST_KINDS:
            raise ProfileError("invalid_host_kind")
        expected["host_kind"] = raw["host_kind"]
    for digest_field in (
        "home_manager_generation_digest",
        "nix_system_generation_digest",
        "doctrine_kernel_digest",
        "flake_lock_digest",
        "workspace_identity_digest",
    ):
        if digest_field in raw and raw[digest_field] not in (None, ""):
            expected[digest_field] = require_digest(raw[digest_field], field=digest_field)
    if "config_revision" in raw and raw["config_revision"] not in (None, ""):
        if not isinstance(raw["config_revision"], str) or not REVISION_RE.fullmatch(raw["config_revision"]):
            raise ProfileError("invalid_config_revision")
        expected["config_revision"] = raw["config_revision"]
    for identity_field in ("paimos_instance", "paimos_deployment", "paimos_project_key"):
        if identity_field in raw and raw[identity_field] not in (None, ""):
            expected[identity_field] = require_identity(raw[identity_field], field=identity_field)
    if "account_label" in raw and raw["account_label"] not in (None, ""):
        if raw["account_label"] not in ACCOUNT_LABELS:
            raise ProfileError("invalid_account_label")
        expected["account_label"] = raw["account_label"]
    if "account_key" in raw and raw["account_key"] not in (None, ""):
        value = raw["account_key"]
        if not isinstance(value, str) or not ACCOUNT_KEY_RE.fullmatch(value) or value in ACCOUNT_LABELS or value == "local_probe":
            raise ProfileError("invalid_account_key")
        expected["account_key"] = value
    if "harness" in raw and raw["harness"] not in (None, ""):
        if raw["harness"] not in HARNESSES:
            raise ProfileError("invalid_harness")
        expected["harness"] = raw["harness"]
    if "model" in raw and raw["model"] not in (None, ""):
        if not isinstance(raw["model"], str) or not IDENTITY_RE.fullmatch(raw["model"]):
            raise ProfileError("invalid_model")
        expected["model"] = raw["model"]
    if "effort" in raw and raw["effort"] not in (None, ""):
        if raw["effort"] not in EFFORTS:
            raise ProfileError("invalid_effort")
        expected["effort"] = raw["effort"]
    if "workspace_mode" in raw and raw["workspace_mode"] not in (None, ""):
        if raw["workspace_mode"] not in WORKSPACE_MODES:
            raise ProfileError("invalid_workspace_mode")
        expected["workspace_mode"] = raw["workspace_mode"]
    if "tools" in raw and raw["tools"] not in (None, []):
        expected["tools"] = list(
            _parse_closed_list(raw["tools"], allowed=None, reason="invalid_tool", limit=MAX_TOOLS, pattern=TOOL_RE)
        )
    return expected


def _parse_closed_list(
    value: Any,
    *,
    allowed: tuple[str, ...] | None,
    reason: str,
    limit: int,
    pattern: re.Pattern[str] | None = None,
) -> tuple[str, ...]:
    if not isinstance(value, list):
        raise ProfileError(reason)
    if len(value) > limit:
        raise ProfileError(reason)
    out: list[str] = []
    seen: set[str] = set()
    for item in value:
        if not isinstance(item, str):
            raise ProfileError(reason)
        if allowed is not None and item not in allowed:
            raise ProfileError(reason)
        if pattern is not None and not pattern.fullmatch(item):
            raise ProfileError(reason)
        if item in seen:
            raise ProfileError(reason)
        seen.add(item)
        out.append(item)
    return tuple(out)


def _require_check_inputs(required: tuple[str, ...], expected: Mapping[str, Any], inputs: Mapping[str, str]) -> None:
    if "host_kind" in required and "host_kind" not in expected:
        raise ProfileError("missing_host_kind")
    if "activated_generation" in required:
        host_kind = expected.get("host_kind")
        if host_kind == "macos-home-manager" and "home_manager_generation_digest" not in expected:
            raise ProfileError("missing_home_manager_generation_digest")
        if host_kind == "nixos-home-manager" and "nix_system_generation_digest" not in expected:
            raise ProfileError("missing_nix_system_generation_digest")
        if host_kind not in HOST_KINDS:
            raise ProfileError("missing_host_kind")
    if "doctrine_loader" in required:
        if "doctrine_kernel_digest" not in expected:
            raise ProfileError("missing_doctrine_kernel_digest")
        if "doctrine_kernel" not in inputs or "doctrine_loader" not in inputs:
            raise ProfileError("missing_doctrine_inputs")
    if "workspace_isolation" in required:
        if "workspace_identity_digest" not in expected or "workspace_root" not in inputs:
            raise ProfileError("missing_workspace_inputs")
    if "tool_prerequisites" in required and "tools" not in expected:
        raise ProfileError("missing_tools")
    if "paimos_runtime_doctor" in required:
        if "paimos_instance" not in expected or "paimos_deployment" not in expected:
            raise ProfileError("missing_paimos_runtime")
    if "paimos_account" in required:
        if "account_label" not in expected or "harness" not in expected:
            raise ProfileError("missing_account_expected")
    if "dispatch_profile" in required:
        if "harness" not in expected or "model" not in expected or "effort" not in expected:
            raise ProfileError("missing_dispatch_expected")


def expected_revisions(profile: Profile) -> dict[str, str]:
    out: dict[str, str] = {}
    for key in (
        "config_revision",
        "doctrine_kernel_digest",
        "home_manager_generation_digest",
        "nix_system_generation_digest",
        "flake_lock_digest",
        "workspace_identity_digest",
    ):
        value = profile.expected.get(key)
        if isinstance(value, str):
            out[key] = value
    return out


def aggregate(profile: Profile, checks: list[CheckResult], *, now: datetime) -> Evidence:
    by_id = {item.id: item for item in checks}
    required_statuses = []
    optional_warn = False
    next_action = "none"
    for check_id in profile.required_checks:
        result = by_id.get(check_id) or CheckResult(check_id, "unknown", "missing_required_evidence")
        required_statuses.append(result.status)
        if next_action == "none" and result.status != "pass":
            next_action = _next_action(result)
    for check_id in profile.optional_checks:
        result = by_id.get(check_id)
        if result is not None and result.status == "warn":
            optional_warn = True
        elif result is not None and result.status in BLOCKING_UNKNOWN:
            optional_warn = True
        elif result is not None and result.status == "fail":
            optional_warn = True

    if any(status in BLOCKING_UNKNOWN for status in required_statuses):
        overall = "unavailable"
    elif any(status == "fail" for status in required_statuses):
        overall = "needs_setup"
    elif all(status == "pass" for status in required_statuses):
        overall = "ready"
    else:
        overall = "unavailable"
    if overall == "ready":
        next_action = "none"
        if optional_warn:
            # Warnings do not demote ready; they remain on the optional checks.
            pass
    evidence = Evidence(
        status=overall,
        observed_at=now,
        expires_at=now + timedelta(seconds=profile.observation_ttl_seconds),
        profile_id=profile.profile_id,
        profile_digest=profile.digest,
        context=dict(profile.identities),
        expected_revisions=expected_revisions(profile),
        checks=list(checks),
        next_action=next_action if overall != "ready" else "none",
    )
    _assert_export_clean(evidence.as_dict())
    return evidence


def _next_action(result: CheckResult) -> str:
    mapping = {
        "host_kind": "adopt_nix_home_manager",
        "activated_generation": "activate_home_manager",
        "doctrine_loader": "repair_doctrine_loader",
        "workspace_isolation": "select_declared_workspace",
        "tool_prerequisites": "install_declared_tools",
        "paimos_runtime_doctor": "configure_paimos_instance",
        "paimos_account": "verify_named_account",
        "dispatch_profile": "install_missing_integration",
    }
    if result.reason in {
        "non_nix_onboarding_unavailable",
        "host_kind_unsupported",
        "nixos_unavailable_on_macos",
    }:
        return "adopt_nix_home_manager"
    if result.reason == "generation_not_activated" and result.id == "activated_generation":
        return "activate_home_manager"
    if result.reason == "nixos_generation_not_activated":
        return "activate_nixos_generation"
    if result.reason.startswith("missing_integration"):
        return "install_missing_integration"
    if result.reason in {"runtime_action_required", "runtime_not_ready"}:
        return "run_paimos_runtime_setup"
    return mapping.get(result.id, "none")


def _assert_export_clean(payload: Mapping[str, Any]) -> None:
    encoded = json.dumps(payload, sort_keys=True)
    lowered = encoded.lower()
    forbidden = (
        "http://",
        "https://",
        "/users/",
        "/home/",
        "/nix/store/",
        "begin ",
        "@",
    )
    for item in forbidden:
        if item in lowered:
            raise ProfileError("export_redaction")


def usage_error_payload(reason: str) -> dict[str, str]:
    return {
        "contract_version": CONTRACT_VERSION,
        "error": "profile_invalid",
        "reason": sanitize_exported_reason(reason),
    }


def exit_status(evidence_status: str) -> int:
    return {"ready": 0, "needs_setup": 1, "unavailable": 3}.get(evidence_status, 3)
