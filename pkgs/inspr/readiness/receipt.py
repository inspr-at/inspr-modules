# SPDX-License-Identifier: AGPL-3.0-only
"""Closed consumer contract for server-accepted Paimos workspace observations."""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from uuid import UUID

from .contract import (ACCOUNT_LABELS, ACCOUNT_KEY_RE, CHECK_STATUSES, CONTRACT_VERSION,
                       DOCTOR_CODE_RE, DIGEST_RE, ProfileError, WORKSPACE_MODES,
                       require_mapping, digest_text)

BINDING_FIELDS = frozenset({"project_id", "runtime_id", "runtime_generation", "account_label",
    "dispatch_profile_id", "dispatch_profile_version", "workspace_handle", "workspace_identity",
    "workspace_mode", "baseline_digest"})
RECEIPT_FIELDS = BINDING_FIELDS | {"account_key", "contract_version", "intent_id", "host_kind",
    "status", "next_action", "observed_at", "expires_at", "checks"}
LABEL = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")
HEX = re.compile(r"^[0-9a-f]{64}$")


def uuid_valid(value):
    try:
        return isinstance(value, str) and str(UUID(value)) == value
    except (ValueError, AttributeError):
        return False


def parse_binding(value):
    data = require_mapping(value, "invalid_readiness_binding")
    if set(data) - (BINDING_FIELDS | {"account_key"}) or BINDING_FIELDS - set(data):
        raise ProfileError("invalid_readiness_binding")
    if type(data["project_id"]) is not int or not 0 < data["project_id"] < 2**63:
        raise ProfileError("invalid_readiness_binding")
    for key in ("runtime_id", "runtime_generation"):
        if not uuid_valid(data[key]):
            raise ProfileError("invalid_readiness_binding")
    for key in ("dispatch_profile_id", "dispatch_profile_version", "workspace_handle"):
        if not isinstance(data[key], str) or not LABEL.fullmatch(data[key]):
            raise ProfileError("invalid_readiness_binding")
    if data["account_label"] not in ACCOUNT_LABELS or data["workspace_mode"] not in WORKSPACE_MODES:
        raise ProfileError("invalid_readiness_binding")
    if "account_key" in data and (not isinstance(data["account_key"], str) or not ACCOUNT_KEY_RE.fullmatch(data["account_key"])):
        raise ProfileError("invalid_readiness_binding")
    for key, pattern in (("workspace_identity", HEX), ("baseline_digest", DIGEST_RE)):
        if not isinstance(data[key], str) or not pattern.fullmatch(data[key]):
            raise ProfileError("invalid_readiness_binding")
    return dict(data)


def validate_receipt(raw: bytes, binding: dict, *, now: datetime):
    if not isinstance(raw, bytes) or not 0 < len(raw) <= 16384:
        raise ProfileError("invalid_readiness_receipt")
    def closed_object(pairs):
        out = {}
        for key, value in pairs:
            if key in out:
                raise ProfileError("invalid_readiness_receipt")
            out[key] = value
        return out
    try:
        data = json.loads(raw, object_pairs_hook=closed_object)
    except (ValueError, UnicodeDecodeError):
        raise ProfileError("invalid_readiness_receipt") from None
    data = require_mapping(data, "invalid_readiness_receipt")
    if set(data) - RECEIPT_FIELDS or (RECEIPT_FIELDS - {"account_key"}) - set(data):
        raise ProfileError("invalid_readiness_receipt")
    if data["contract_version"] != CONTRACT_VERSION or not uuid_valid(data["intent_id"]):
        raise ProfileError("invalid_readiness_receipt")
    observed_binding = parse_binding({k: data[k] for k in BINDING_FIELDS | {"account_key"} if k in data})
    if observed_binding != binding:
        raise ProfileError("readiness_receipt_binding_mismatch")
    def timestamp(key):
        value = data[key]
        if not isinstance(value, str) or len(value) > 40:
            raise ProfileError("invalid_readiness_receipt")
        try:
            parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            raise ProfileError("invalid_readiness_receipt") from None
        if parsed.tzinfo is None:
            raise ProfileError("invalid_readiness_receipt")
        return parsed.astimezone(timezone.utc)
    observed, expires = timestamp("observed_at"), timestamp("expires_at")
    if observed > now or expires <= now or expires <= observed or (expires-observed).total_seconds() > 3600:
        raise ProfileError("readiness_receipt_stale")
    if data["status"] not in ("ready", "needs_setup", "unavailable"):
        raise ProfileError("invalid_readiness_receipt")
    for field in ("host_kind", "next_action"):
        if not isinstance(data[field], str) or not DOCTOR_CODE_RE.fullmatch(data[field].replace("-", "_")):
            raise ProfileError("invalid_readiness_receipt")
    checks = data["checks"]
    if not isinstance(checks, list) or not 0 < len(checks) <= 8:
        raise ProfileError("invalid_readiness_receipt")
    seen = set()
    workspace = None
    for check in checks:
        check = require_mapping(check, "invalid_readiness_receipt")
        if set(check) - {"id", "status", "reason", "digest"} or {"id", "status", "reason"} - set(check):
            raise ProfileError("invalid_readiness_receipt")
        for key in ("id", "reason"):
            if not isinstance(check[key], str) or not DOCTOR_CODE_RE.fullmatch(check[key]):
                raise ProfileError("invalid_readiness_receipt")
        if check["id"] in seen or check["status"] not in CHECK_STATUSES:
            raise ProfileError("invalid_readiness_receipt")
        seen.add(check["id"])
        if "digest" in check and (not isinstance(check["digest"], str) or not DIGEST_RE.fullmatch(check["digest"])):
            raise ProfileError("invalid_readiness_receipt")
        if check["id"] == "workspace_isolation":
            workspace = check
    if workspace is None:
        raise ProfileError("readiness_receipt_workspace_missing")
    if workspace["status"] == "pass" and workspace.get("digest") != digest_text(binding["workspace_identity"]):
        raise ProfileError("readiness_receipt_workspace_mismatch")
    return data["status"], workspace["status"], expires
