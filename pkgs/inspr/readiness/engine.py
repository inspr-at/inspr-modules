# SPDX-License-Identifier: AGPL-3.0-only
"""Read-only readiness engine: closed probes, bounded subprocesses, cached evidence."""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Mapping

from . import CONTRACT_VERSION
from .contract import (
    ACCOUNT_PROBE_OUTPUT_BYTES,
    ACCOUNT_PROBE_TIMEOUT_SECONDS,
    CACHE_SCHEMA,
    DOCTOR_CODE_RE,
    DOCTOR_LAYER_NAMES,
    DOCTOR_STATES,
    MAX_OUTPUT_BYTES,
    MAX_PROFILE_BYTES,
    Profile,
    ProfileError,
    SUBPROCESS_TIMEOUT_SECONDS,
    CheckResult,
    Evidence,
    aggregate,
    closed_reason,
    digest_bytes,
    digest_text,
    expected_revisions,
    load_profile_bytes,
    parse_now,
    sanitize_exported_reason,
    usage_error_payload,
)

KERNEL_REF = "@./doctrine/docs/AGENTS-KERNEL.md"
LEGACY_LOADER = re.compile(r"@\./doctrine/docs/AGENTS-(CORE|PROFILE-MARKUS)\.md")
STORE_BASENAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]{0,230}$")
GIT_IDENTITY_RE = re.compile(r"^[0-9a-f]{40,64}$")
PAIMOS_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")
INHERITED_ENV = (
    "PATH",
    "HOME",
    "USER",
    "LOGNAME",
    "SHELL",
    "TMPDIR",
    "TMP",
    "TEMP",
    "LANG",
    "LC_ALL",
    "LC_CTYPE",
    "LC_MESSAGES",
    "TZ",
    "XDG_RUNTIME_DIR",
    "XDG_CACHE_HOME",
    "XDG_CONFIG_HOME",
    "XDG_STATE_HOME",
    "SSL_CERT_FILE",
    "SSL_CERT_DIR",
    "CURL_CA_BUNDLE",
    "REQUESTS_CA_BUNDLE",
)
BLOCKED_ENV = frozenset(
    {
        "PAIMOS_URL",
        "PAIMOS_API_KEY",
        "PPM_URL",
        "PPMAPIKEY",
        "GH_TOKEN",
        "GITHUB_TOKEN",
        "OPENAI_API_KEY",
        "ANTHROPIC_API_KEY",
    }
)


class ProbeTimeout(Exception):
    pass


class ProbeOutputBound(Exception):
    pass


@dataclass
class RunResult:
    argv: tuple[str, ...]
    stdout: bytes
    stderr: bytes
    exit_code: int


Which = Callable[[str], str | None]
Runner = Callable[..., RunResult]
ReadFile = Callable[[str, int], bytes]


@dataclass
class ProbeHost:
    which: Which
    run: Runner
    read_file: ReadFile
    exists: Callable[[str], bool]
    isdir: Callable[[str], bool]
    isfile: Callable[[str], bool]
    islink: Callable[[str], bool]
    realpath: Callable[[str], str]
    readlink: Callable[[str], str]
    listdir: Callable[[str], list[str]]
    environ: Mapping[str, str]
    platform: str
    nixos_marker: bool
    makedirs: Callable[[str], None]
    write_file: Callable[[str, bytes], None]


def real_host(environ: Mapping[str, str] | None = None) -> ProbeHost:
    env = os.environ if environ is None else environ

    def _which(name: str) -> str | None:
        return shutil.which(name, path=env.get("PATH"))

    def _run(
        argv: list[str],
        *,
        timeout: float,
        max_output: int,
        extra_env: Mapping[str, str] | None = None,
        cwd: str | None = None,
    ) -> RunResult:
        return run_closed(
            argv,
            timeout=timeout,
            max_output=max_output,
            environ=env,
            extra_env=extra_env,
            cwd=cwd,
        )

    def _read(path: str, limit: int) -> bytes:
        return read_bounded(path, limit)

    def _write(path: str, data: bytes) -> None:
        directory = os.path.dirname(path)
        os.makedirs(directory, mode=0o700, exist_ok=True)
        tmp = path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
        os.replace(tmp, path)

    return ProbeHost(
        which=_which,
        run=_run,
        read_file=_read,
        exists=os.path.exists,
        isdir=os.path.isdir,
        isfile=os.path.isfile,
        islink=os.path.islink,
        realpath=os.path.realpath,
        readlink=lambda path: os.readlink(path),
        listdir=lambda path: os.listdir(path),
        environ=env,
        platform=sys.platform,
        nixos_marker=os.path.isfile("/etc/NIXOS"),
        makedirs=lambda path: os.makedirs(path, mode=0o700, exist_ok=True),
        write_file=_write,
    )


def run_closed(
    argv: list[str],
    *,
    timeout: float,
    max_output: int,
    environ: Mapping[str, str],
    extra_env: Mapping[str, str] | None = None,
    cwd: str | None = None,
) -> RunResult:
    import subprocess

    if not argv or not argv[0] or any(not isinstance(item, str) or "\x00" in item for item in argv):
        raise ProfileError("invalid_command")
    if cwd is not None and (not cwd.startswith("/") or cwd != os.path.normpath(cwd)):
        raise ProfileError("unsafe_cwd")
    env = operator_env(environ)
    if extra_env:
        env.update(extra_env)
    try:
        completed = subprocess.run(
            argv,
            cwd=cwd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise ProbeTimeout from exc
    stdout = completed.stdout or b""
    stderr = completed.stderr or b""
    if len(stdout) > max_output or len(stderr) > max_output:
        raise ProbeOutputBound
    return RunResult(tuple(argv), stdout, stderr, completed.returncode)


def operator_env(environ: Mapping[str, str]) -> dict[str, str]:
    env: dict[str, str] = {}
    for name in INHERITED_ENV:
        if name in environ and name not in BLOCKED_ENV:
            env[name] = environ[name]
    for name in BLOCKED_ENV:
        env.pop(name, None)
    return env


def read_bounded(path: str, limit: int) -> bytes:
    with open(path, "rb") as handle:
        data = handle.read(limit + 1)
    if len(data) > limit:
        raise ProfileError("input_too_large")
    return data


def evaluate(profile: Profile, host: ProbeHost, *, now: datetime, use_cache: bool = True) -> Evidence:
    cached = load_cache(profile, host, now=now) if use_cache else None
    if cached is not None:
        return cached
    checks: list[CheckResult] = []
    for check_id in (*profile.required_checks, *profile.optional_checks):
        optional = check_id in profile.optional_checks
        checks.append(run_check(check_id, profile, host, optional=optional))
    evidence = aggregate(profile, checks, now=now)
    if use_cache:
        store_cache(profile, host, evidence)
    return evidence


def run_check(check_id: str, profile: Profile, host: ProbeHost, *, optional: bool) -> CheckResult:
    dispatch = {
        "host_kind": probe_host_kind,
        "activated_generation": probe_activated_generation,
        "doctrine_loader": probe_doctrine_loader,
        "workspace_isolation": probe_workspace_isolation,
        "tool_prerequisites": probe_tool_prerequisites,
        "paimos_runtime_doctor": probe_paimos_runtime_doctor,
        "paimos_account": probe_paimos_account,
        "dispatch_profile": probe_dispatch_profile,
    }
    fn = dispatch.get(check_id)
    if fn is None:
        return CheckResult(check_id, "unsupported", "unknown_check")
    try:
        result = fn(profile, host)
    except ProbeTimeout:
        result = CheckResult(check_id, "unknown", "probe_timeout")
    except ProbeOutputBound:
        result = CheckResult(check_id, "unknown", "probe_output_bound")
    except ProfileError as exc:
        result = CheckResult(check_id, "unknown", closed_reason(exc.reason))
    except OSError:
        result = CheckResult(check_id, "unknown", "probe_unavailable")
    if optional and result.status in {"fail", "unknown", "unsupported", "stale"}:
        return CheckResult(result.id, "warn", result.reason, result.digest)
    return result


def probe_host_kind(profile: Profile, host: ProbeHost) -> CheckResult:
    expected = profile.expected["host_kind"]
    observed = observe_host_kind(host)
    if observed == "unsupported":
        return CheckResult("host_kind", "unsupported", "non_nix_onboarding_unavailable")
    if expected == "nixos-home-manager" and host.platform == "darwin":
        return CheckResult("host_kind", "unsupported", "nixos_unavailable_on_macos")
    if observed != expected:
        return CheckResult("host_kind", "fail", "host_kind_mismatch")
    return CheckResult("host_kind", "pass", "host_kind_supported", digest_text(observed))


def observe_host_kind(host: ProbeHost) -> str:
    if host.nixos_marker:
        return "nixos-home-manager"
    if host.platform == "darwin":
        if _home_manager_current(host) or _home_manager_profile(host):
            return "macos-home-manager"
        # macOS without any HM profile is still the expected class if requested,
        # but activation is unproven. Host class is macos; generation probe fails.
        return "macos-home-manager"
    return "unsupported"


def probe_activated_generation(profile: Profile, host: ProbeHost) -> CheckResult:
    expected_kind = profile.expected.get("host_kind")
    if expected_kind == "nixos-home-manager":
        if host.platform == "darwin":
            return CheckResult("activated_generation", "unsupported", "nixos_unavailable_on_macos")
        return _compare_generations(
            "activated_generation",
            activated=_nixos_activated(host),
            installed=_nixos_installed(host),
            expected=profile.expected.get("nix_system_generation_digest"),
            inactive_reason="nixos_generation_not_activated",
            missing_reason="nixos_generation_missing",
        )
    return _compare_generations(
        "activated_generation",
        activated=_home_manager_current(host),
        installed=_home_manager_profile(host),
        expected=profile.expected.get("home_manager_generation_digest"),
        inactive_reason="generation_not_activated",
        missing_reason="home_manager_generation_missing",
    )


def _compare_generations(
    check_id: str,
    *,
    activated: str | None,
    installed: str | None,
    expected: str | None,
    inactive_reason: str,
    missing_reason: str,
) -> CheckResult:
    if not activated:
        if installed:
            return CheckResult(check_id, "fail", inactive_reason)
        return CheckResult(check_id, "fail", missing_reason)
    observed = generation_digest(activated)
    if expected is None:
        return CheckResult(check_id, "unknown", "missing_generation_digest")
    if observed != expected:
        return CheckResult(check_id, "fail", "generation_digest_mismatch", observed)
    if installed and generation_digest(installed) != observed:
        return CheckResult(check_id, "fail", inactive_reason, observed)
    return CheckResult(check_id, "pass", "generation_activated", observed)


def generation_digest(resolved_path: str) -> str:
    base = os.path.basename(resolved_path.rstrip("/"))
    if not STORE_BASENAME_RE.fullmatch(base):
        raise ProfileError("generation_identity_invalid")
    return digest_text(base)


def _home_state(host: ProbeHost) -> str:
    home = host.environ.get("HOME") or ""
    if not home.startswith("/"):
        return ""
    return home


def _home_manager_current(host: ProbeHost) -> str | None:
    home = _home_state(host)
    if not home:
        return None
    return _resolve_generation(host, os.path.join(home, ".local/state/home-manager/gcroots/current-home"))


def _home_manager_profile(host: ProbeHost) -> str | None:
    home = _home_state(host)
    candidates = []
    if home:
        candidates.append(os.path.join(home, ".local/state/nix/profiles/home-manager"))
    user = host.environ.get("USER")
    if user and TOOL_NAME_OK(user):
        candidates.append(f"/nix/var/nix/profiles/per-user/{user}/home-manager")
    for path in candidates:
        resolved = _resolve_generation(host, path)
        if resolved:
            return resolved
    return None


def TOOL_NAME_OK(value: str) -> bool:
    return bool(re.fullmatch(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$", value))


def _nixos_activated(host: ProbeHost) -> str | None:
    return _resolve_generation(host, "/run/current-system")


def _nixos_installed(host: ProbeHost) -> str | None:
    return _resolve_generation(host, "/nix/var/nix/profiles/system")


def _resolve_generation(host: ProbeHost, path: str) -> str | None:
    target = None
    if host.islink(path):
        try:
            target = host.readlink(path)
        except OSError:
            return None
        if not target.startswith("/"):
            target = os.path.normpath(os.path.join(os.path.dirname(path), target))
    elif host.exists(path):
        try:
            target = host.realpath(path)
        except OSError:
            return None
    if not target:
        return None
    base = os.path.basename(target.rstrip("/"))
    if not STORE_BASENAME_RE.fullmatch(base):
        return None
    return target


def probe_doctrine_loader(profile: Profile, host: ProbeHost) -> CheckResult:
    loader = profile.inputs["doctrine_loader"]
    kernel = profile.inputs["doctrine_kernel"]
    if _inside_workspace_executable(profile, host, loader) or _inside_workspace_executable(profile, host, kernel):
        # Reading files from the declared workspace is required; executing is not.
        pass
    try:
        loader_text = host.read_file(loader, MAX_OUTPUT_BYTES).decode("utf-8")
        kernel_bytes = host.read_file(kernel, MAX_PROFILE_BYTES)
    except (OSError, UnicodeDecodeError, ProfileError):
        return CheckResult("doctrine_loader", "fail", "doctrine_unreadable")
    if KERNEL_REF not in loader_text:
        return CheckResult("doctrine_loader", "fail", "doctrine_loader_unwired")
    if LEGACY_LOADER.search(loader_text):
        return CheckResult("doctrine_loader", "fail", "doctrine_loader_legacy")
    observed = digest_bytes(kernel_bytes)
    expected = profile.expected["doctrine_kernel_digest"]
    if observed != expected:
        return CheckResult("doctrine_loader", "fail", "doctrine_hash_mismatch", observed)
    return CheckResult("doctrine_loader", "pass", "doctrine_loader_verified", observed)


def probe_workspace_isolation(profile: Profile, host: ProbeHost) -> CheckResult:
    root = profile.inputs["workspace_root"]
    if not host.isdir(root):
        return CheckResult("workspace_isolation", "fail", "workspace_missing")
    git = _pinned_tool(profile, host, "git")
    if git is None:
        return CheckResult("workspace_isolation", "unknown", "git_unavailable")
    env = {"GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"}
    argv_prefix = [
        git,
        "--no-optional-locks",
        "-c",
        "core.hooksPath=/dev/null",
        "-C",
        root,
    ]
    inside = _git_text(host, argv_prefix + ["rev-parse", "--is-inside-work-tree"], extra_env=env)
    if inside != "true":
        return CheckResult("workspace_isolation", "fail", "workspace_not_git")
    head = _git_text(host, argv_prefix + ["rev-parse", "HEAD"], extra_env=env)
    common = _git_text(host, argv_prefix + ["rev-parse", "--git-common-dir"], extra_env=env)
    git_dir = _git_text(host, argv_prefix + ["rev-parse", "--git-dir"], extra_env=env)
    if not head or not GIT_IDENTITY_RE.fullmatch(head):
        return CheckResult("workspace_isolation", "unknown", "workspace_head_unverified")
    if not git_dir or not common:
        return CheckResult("workspace_isolation", "unknown", "workspace_git_unverified")
    is_worktree = git_dir != common
    mode = profile.expected.get("workspace_mode", "exclusive")
    identity = workspace_identity_digest(head, is_worktree=is_worktree, mode=mode)
    expected = profile.expected["workspace_identity_digest"]
    if identity != expected:
        return CheckResult("workspace_isolation", "fail", "workspace_identity_mismatch", identity)
    return CheckResult("workspace_isolation", "pass", "workspace_verified", identity)


def workspace_identity_digest(head: str, *, is_worktree: bool, mode: str) -> str:
    return digest_text(f"{head}|worktree={int(is_worktree)}|mode={mode}")


def _git_text(host: ProbeHost, argv: list[str], extra_env: Mapping[str, str]) -> str:
    result = host.run(argv, timeout=5, max_output=4096, extra_env=extra_env)
    if result.exit_code != 0:
        return ""
    text = result.stdout.decode("utf-8", "replace").strip()
    if not text or "\n" in text or "\x00" in text:
        return ""
    return text


def probe_tool_prerequisites(profile: Profile, host: ProbeHost) -> CheckResult:
    tools = profile.expected.get("tools") or []
    observed = []
    for name in tools:
        pinned = _pinned_tool(profile, host, name)
        if pinned is None:
            return CheckResult("tool_prerequisites", "fail", "declared_tool_missing")
        if _inside_workspace_executable(profile, host, pinned):
            return CheckResult("tool_prerequisites", "fail", "workspace_executable_refused")
        observed.append(os.path.basename(pinned))
    digest = digest_text("|".join(observed))
    flake_lock = profile.inputs.get("flake_lock")
    expected_lock = profile.expected.get("flake_lock_digest")
    if expected_lock:
        if not flake_lock:
            return CheckResult("tool_prerequisites", "unknown", "missing_flake_lock_input")
        try:
            actual = digest_bytes(host.read_file(flake_lock, MAX_PROFILE_BYTES))
        except (OSError, ProfileError):
            return CheckResult("tool_prerequisites", "fail", "flake_lock_unreadable")
        if actual != expected_lock:
            return CheckResult("tool_prerequisites", "fail", "flake_lock_digest_mismatch", actual)
        digest = actual
    return CheckResult("tool_prerequisites", "pass", "tools_verified", digest)


def _pinned_tool(profile: Profile, host: ProbeHost, name: str) -> str | None:
    raw = host.which(name)
    if not raw:
        return None
    try:
        canonical = host.realpath(raw)
    except OSError:
        return None
    if not host.isfile(canonical):
        return None
    if _inside_workspace_executable(profile, host, canonical):
        return None
    return canonical


def _inside_workspace_executable(profile: Profile, host: ProbeHost, path: str) -> bool:
    root = profile.inputs.get("workspace_root")
    if not root:
        return False
    try:
        real_path = host.realpath(path)
        real_root = host.realpath(root)
    except OSError:
        return False
    return real_path == real_root or real_path.startswith(real_root.rstrip("/") + "/")


def probe_paimos_runtime_doctor(profile: Profile, host: ProbeHost) -> CheckResult:
    paimos = _pinned_tool(profile, host, "paimos")
    if paimos is None:
        return CheckResult("paimos_runtime_doctor", "unsupported", "missing_integration_paimos_runtime_doctor")
    instance = profile.expected["paimos_instance"]
    deployment = profile.expected["paimos_deployment"]
    if not PAIMOS_NAME_RE.fullmatch(instance) or not PAIMOS_NAME_RE.fullmatch(deployment):
        return CheckResult("paimos_runtime_doctor", "fail", "invalid_runtime_identity")
    argv = [
        paimos,
        "--json",
        "--instance",
        instance,
        "runtime",
        "doctor",
        "--expect-deployment-instance",
        deployment,
    ]
    project = profile.expected.get("paimos_project_key")
    if project:
        argv.extend(["--project", project])
    try:
        result = host.run(argv, timeout=SUBPROCESS_TIMEOUT_SECONDS, max_output=MAX_OUTPUT_BYTES)
    except ProbeTimeout:
        return CheckResult("paimos_runtime_doctor", "unknown", "probe_timeout")
    except ProbeOutputBound:
        return CheckResult("paimos_runtime_doctor", "unknown", "probe_output_bound")
    report = parse_runtime_doctor(result.stdout)
    if report is None:
        return CheckResult("paimos_runtime_doctor", "unknown", "runtime_evidence_invalid")
    if report["instance"] != deployment and report["instance"] != instance:
        return CheckResult("paimos_runtime_doctor", "fail", "runtime_instance_mismatch")
    layers = {layer["name"]: layer for layer in report["layers"]}
    auth = layers.get("cli_auth")
    identity = layers.get("server_identity")
    if auth is None or identity is None:
        return CheckResult("paimos_runtime_doctor", "unknown", "runtime_layers_incomplete")
    if auth["state"] == "unknown" or identity["state"] == "unknown":
        return CheckResult("paimos_runtime_doctor", "unknown", "runtime_auth_unverified")
    if auth["state"] == "action_required" or identity["state"] == "action_required":
        return CheckResult("paimos_runtime_doctor", "fail", "runtime_action_required")
    if auth["state"] not in {"known", "repaired"} or identity["state"] not in {"known", "repaired"}:
        return CheckResult("paimos_runtime_doctor", "unknown", "runtime_auth_unverified")
    blocking = []
    for layer in report["layers"]:
        if layer["name"] not in DOCTOR_LAYER_NAMES:
            continue
        if layer["state"] not in {"known", "repaired"}:
            blocking.append(layer)
    digest = digest_text("|".join(f"{layer['name']}={layer['state']}:{layer['code']}" for layer in report["layers"] if layer["name"] in DOCTOR_LAYER_NAMES))
    if blocking:
        # A true ready boolean from the payload is never sufficient on its own.
        if any(layer["state"] == "unknown" for layer in blocking):
            return CheckResult("paimos_runtime_doctor", "unknown", "runtime_layer_unknown", digest)
        return CheckResult("paimos_runtime_doctor", "fail", "runtime_not_ready", digest)
    if "runtime_ready" in profile.requested_capabilities and report.get("ready") is not True:
        # Layers are the authority; ready=false with all known is still not ready.
        return CheckResult("paimos_runtime_doctor", "fail", "runtime_not_ready", digest)
    return CheckResult("paimos_runtime_doctor", "pass", "runtime_doctor_verified", digest)


def parse_runtime_doctor(raw: bytes) -> dict[str, Any] | None:
    if not raw or len(raw) > MAX_OUTPUT_BYTES:
        return None
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    instance = payload.get("instance")
    layers = payload.get("layers")
    ready = payload.get("ready")
    if not isinstance(instance, str) or not PAIMOS_NAME_RE.fullmatch(instance):
        return None
    if not isinstance(ready, bool) or not isinstance(layers, list) or len(layers) > 64:
        return None
    parsed = []
    for item in layers:
        if not isinstance(item, dict):
            return None
        name = item.get("name")
        state = item.get("state")
        code = item.get("code")
        if name not in DOCTOR_LAYER_NAMES or state not in DOCTOR_STATES:
            return None
        if not isinstance(code, str) or not DOCTOR_CODE_RE.fullmatch(code):
            return None
        parsed.append({"name": name, "state": state, "code": code})
    # Paths, emails, bootstrap strings and raw action text are dropped here.
    return {"instance": instance, "ready": ready, "layers": parsed}


def probe_paimos_account(profile: Profile, host: ProbeHost) -> CheckResult:
    harness = profile.expected["harness"]
    expected_label = profile.expected["account_label"]
    if profile.expected.get("account_key") or "named_account" in profile.requested_capabilities:
        # Named-account proof lives in Paimos agentd (account/read / registry).
        # This CLI must not start a worker/model turn or read the private registry.
        return CheckResult("paimos_account", "unsupported", "missing_integration_paimos_named_account_probe")
    if harness == "claude":
        return _claude_account_label(profile, host, expected_label)
    if harness == "codex":
        return _codex_account_label(profile, host, expected_label)
    return CheckResult("paimos_account", "unsupported", "missing_integration_harness_account_probe")


def _claude_account_label(profile: Profile, host: ProbeHost, expected_label: str) -> CheckResult:
    binary = _pinned_tool(profile, host, "claude")
    if binary is None:
        return CheckResult("paimos_account", "unsupported", "missing_integration_claude_account_probe")
    result = host.run(
        [binary, "auth", "status", "--json"],
        timeout=ACCOUNT_PROBE_TIMEOUT_SECONDS,
        max_output=ACCOUNT_PROBE_OUTPUT_BYTES,
    )
    if result.exit_code != 0:
        return CheckResult("paimos_account", "unknown", "account_probe_unavailable")
    try:
        payload = json.loads(result.stdout.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return CheckResult("paimos_account", "unknown", "account_probe_invalid")
    if not isinstance(payload, dict) or payload.get("loggedIn") is not True:
        return CheckResult("paimos_account", "fail", "account_unauthenticated")
    method = payload.get("authMethod")
    subscription = payload.get("subscriptionType")
    label = "unknown"
    if method == "claude.ai" and subscription in {"max", "pro", "team", "enterprise"}:
        label = "claude_ai_" + subscription
    elif method == "console":
        label = "console"
    if label == "unknown":
        return CheckResult("paimos_account", "unknown", "account_label_unknown")
    if label != expected_label:
        return CheckResult("paimos_account", "fail", "account_mismatch")
    return CheckResult("paimos_account", "pass", "account_label_verified", digest_text(label))


def _codex_account_label(profile: Profile, host: ProbeHost, expected_label: str) -> CheckResult:
    binary = _pinned_tool(profile, host, "codex")
    if binary is None:
        return CheckResult("paimos_account", "unsupported", "missing_integration_codex_account_probe")
    result = host.run(
        [binary, "login", "status"],
        timeout=ACCOUNT_PROBE_TIMEOUT_SECONDS,
        max_output=ACCOUNT_PROBE_OUTPUT_BYTES,
    )
    if result.exit_code != 0:
        return CheckResult("paimos_account", "unknown", "account_probe_unavailable")
    text = (result.stdout or result.stderr).decode("utf-8", "replace").strip()
    if not text or "\n" in text:
        return CheckResult("paimos_account", "unknown", "account_probe_invalid")
    lowered = text.lower()
    if "chatgpt" in lowered:
        label = "chatgpt"
    elif "api" in lowered:
        label = "api_key"
    else:
        return CheckResult("paimos_account", "unknown", "account_label_unknown")
    if label != expected_label:
        return CheckResult("paimos_account", "fail", "account_mismatch")
    return CheckResult("paimos_account", "pass", "account_label_verified", digest_text(label))


def probe_dispatch_profile(profile: Profile, host: ProbeHost) -> CheckResult:
    # Runtime doctor only attests that an immutable catalog is reachable.
    # Matching a requested model/effort requires a native catalog comparison
    # that this CLI does not invent from unverified JSON.
    del host
    if profile.expected.get("model") or profile.expected.get("effort") or "dispatch_profile" in profile.requested_capabilities:
        return CheckResult("dispatch_profile", "unsupported", "missing_integration_paimos_dispatch_profile_match")
    return CheckResult("dispatch_profile", "unknown", "dispatch_profile_unverified")


def cache_path(profile: Profile, host: ProbeHost) -> str | None:
    directory = profile.inputs.get("cache_dir")
    if directory:
        return os.path.join(directory, profile.digest[7:] + ".json")
    xdg = host.environ.get("XDG_CACHE_HOME")
    home = host.environ.get("HOME")
    if xdg and xdg.startswith("/"):
        root = os.path.join(xdg, "inspr/readiness")
    elif home and home.startswith("/"):
        root = os.path.join(home, ".cache/inspr/readiness")
    else:
        return None
    return os.path.join(root, profile.digest[7:] + ".json")


def load_cache(profile: Profile, host: ProbeHost, *, now: datetime) -> Evidence | None:
    path = cache_path(profile, host)
    if not path or not host.isfile(path):
        return None
    try:
        raw = host.read_file(path, MAX_OUTPUT_BYTES)
        payload = json.loads(raw.decode("utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError, ProfileError):
        return None
    if not isinstance(payload, dict) or payload.get("cache_schema") != CACHE_SCHEMA:
        return None
    if payload.get("profile_digest") != profile.digest:
        return None
    if payload.get("expected_revisions") != expected_revisions(profile):
        return None
    if payload.get("context") != profile.identities:
        return None
    evidence_raw = payload.get("evidence")
    if not isinstance(evidence_raw, dict):
        return None
    try:
        observed = datetime.fromisoformat(str(evidence_raw.get("observed_at", "")).replace("Z", "+00:00"))
        expires = datetime.fromisoformat(str(evidence_raw.get("expires_at", "")).replace("Z", "+00:00"))
    except ValueError:
        return None
    if expires.tzinfo is None or observed.tzinfo is None:
        return None
    if now >= expires.astimezone(timezone.utc):
        stale = _evidence_from_dict(profile, evidence_raw, now=now)
        if stale is None:
            return None
        stale.status = "unavailable"
        for item in stale.checks:
            if item.id in profile.required_checks:
                item.status = "stale"
                item.reason = "cached_evidence_expired"
        stale.next_action = "none"
        return aggregate(profile, stale.checks, now=now)
    return _evidence_from_dict(profile, evidence_raw, now=now)


def store_cache(profile: Profile, host: ProbeHost, evidence: Evidence) -> None:
    path = cache_path(profile, host)
    if not path:
        return
    directory = os.path.dirname(path)
    try:
        host.makedirs(directory)
        payload = {
            "cache_schema": CACHE_SCHEMA,
            "contract_version": CONTRACT_VERSION,
            "profile_digest": profile.digest,
            "context": dict(profile.identities),
            "expected_revisions": expected_revisions(profile),
            "evidence": evidence.as_dict(),
        }
        encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        if len(encoded) > MAX_OUTPUT_BYTES:
            return
        host.write_file(path, encoded)
    except OSError:
        return


def _evidence_from_dict(profile: Profile, raw: Mapping[str, Any], *, now: datetime) -> Evidence | None:
    checks_raw = raw.get("checks")
    if not isinstance(checks_raw, list):
        return None
    checks: list[CheckResult] = []
    for item in checks_raw:
        if not isinstance(item, dict):
            return None
        check_id = item.get("id")
        status = item.get("status")
        reason = item.get("reason")
        if check_id not in profile.required_checks and check_id not in profile.optional_checks:
            return None
        if status not in {"pass", "fail", "warn", "unknown", "unsupported", "stale"}:
            return None
        checks.append(CheckResult(str(check_id), str(status), sanitize_exported_reason(str(reason)), item.get("digest") if isinstance(item.get("digest"), str) else None))
    return aggregate(profile, checks, now=now)


def load_profile_file(path: str) -> Profile:
    if not path.startswith("/") or path != os.path.normpath(path):
        raise ProfileError("unsafe_profile_path")
    info = os.stat(path, follow_symlinks=True)
    if not stat.S_ISREG(info.st_mode):
        raise ProfileError("unsafe_profile_path")
    if info.st_size > MAX_PROFILE_BYTES:
        raise ProfileError("profile_size")
    with open(path, "rb") as handle:
        return load_profile_bytes(handle.read(MAX_PROFILE_BYTES + 1))


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    json_only = False
    use_cache = True
    profile_path = None
    while args:
        item = args.pop(0)
        if item in {"-h", "--help"}:
            sys.stdout.write(HELP)
            return 0
        if item == "--json":
            json_only = True
        elif item == "--no-cache":
            use_cache = False
        elif item.startswith("--profile="):
            profile_path = item.split("=", 1)[1]
        elif item == "--profile":
            if not args:
                return _usage("missing_profile")
            profile_path = args.pop(0)
        else:
            return _usage("unknown_flag")
    if not profile_path:
        return _usage("missing_profile")
    try:
        if not profile_path.startswith("/"):
            profile_path = str(Path(profile_path).resolve())
        profile = load_profile_file(profile_path)
        now = parse_now(os.environ.get("INSPR_READINESS_NOW"))
        evidence = evaluate(profile, real_host(), now=now, use_cache=use_cache)
    except ProfileError as exc:
        return _usage(exc.reason)
    encoded = json.dumps(evidence.as_dict(), sort_keys=True, indent=2)
    sys.stdout.write(encoded + "\n")
    if not json_only:
        sys.stderr.write(
            f"inspr readiness: {evidence.status} ({evidence.profile_id}) next={evidence.next_action}\n"
        )
    return {"ready": 0, "needs_setup": 1, "unavailable": 3}[evidence.status]


def _usage(reason: str) -> int:
    payload = usage_error_payload(reason)
    sys.stdout.write(json.dumps(payload, sort_keys=True) + "\n")
    return 2


HELP = """inspr readiness — read-only, machine-readable development-machine probe.

Usage:
  inspr readiness --profile PATH [--json] [--no-cache]

Flags:
  --profile PATH   Operator-owned JSON profile (not sourced as shell).
  --json           JSON evidence only on stdout.
  --no-cache       Ignore and do not write bounded evidence cache.
  -h, --help       Show this help.

Exit codes:
  0  ready
  1  needs_setup
  2  profile / usage error
  3  unavailable

This command never heals, activates Nix, switches accounts, starts a
worker/model turn, or treats browser JSON as proof. Live launch gating
is a separate Paimos concern.
"""
