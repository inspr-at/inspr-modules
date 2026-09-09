"""Minimal deterministic YAML emitter for Traefik file-provider documents."""

from __future__ import annotations

from typing import Any


def emit_yaml(document: dict[str, Any], header: str = "") -> str:
    lines: list[str] = []
    if header:
        for raw in header.splitlines():
            lines.append(raw if raw.startswith("#") or raw == "" else f"# {raw}")
        if lines and lines[-1] != "":
            lines.append("")
    _emit_mapping(document, lines, indent=0)
    return "\n".join(lines) + "\n"


def _emit_mapping(mapping: dict[str, Any], lines: list[str], indent: int) -> None:
    prefix = "  " * indent
    if not mapping:
        raise ValueError("YAML emitter refuses empty mappings; use an explicit value")
    for key, value in mapping.items():
        key_text = _plain_key(key)
        _emit_key_value(f"{prefix}{key_text}:", value, lines, indent)


def _emit_key_value(key_line: str, value: Any, lines: list[str], indent: int) -> None:
    if value is None:
        return
    if isinstance(value, dict):
        if not value:
            lines.append(f"{key_line} {{}}")
            return
        lines.append(key_line)
        _emit_mapping(value, lines, indent + 1)
        return
    if isinstance(value, list):
        if not value:
            lines.append(f"{key_line} []")
            return
        lines.append(key_line)
        _emit_list(value, lines, indent + 1)
        return
    lines.append(f"{key_line} {_scalar(value)}")


def _emit_list(values: list[Any], lines: list[str], indent: int) -> None:
    prefix = "  " * indent
    for value in values:
        if isinstance(value, dict):
            if not value:
                lines.append(f"{prefix}- {{}}")
                continue
            first = True
            for key, item in value.items():
                key_text = _plain_key(key)
                if first:
                    if isinstance(item, (dict, list)) and item:
                        lines.append(f"{prefix}- {key_text}:")
                        if isinstance(item, dict):
                            _emit_mapping(item, lines, indent + 2)
                        else:
                            _emit_list(item, lines, indent + 2)
                    elif isinstance(item, dict):
                        lines.append(f"{prefix}- {key_text}: {{}}")
                    else:
                        lines.append(f"{prefix}- {key_text}: {_scalar(item)}")
                    first = False
                    continue
                if isinstance(item, dict):
                    if not item:
                        lines.append(f"{prefix}  {key_text}: {{}}")
                    else:
                        lines.append(f"{prefix}  {key_text}:")
                        _emit_mapping(item, lines, indent + 2)
                elif isinstance(item, list):
                    if not item:
                        lines.append(f"{prefix}  {key_text}: []")
                    else:
                        lines.append(f"{prefix}  {key_text}:")
                        _emit_list(item, lines, indent + 2)
                else:
                    lines.append(f"{prefix}  {key_text}: {_scalar(item)}")
            continue
        lines.append(f"{prefix}- {_scalar(value)}")


def _plain_key(key: str) -> str:
    if not isinstance(key, str) or not key:
        raise ValueError("YAML keys must be non-empty strings")
    if all(c.isalnum() or c in "-_" for c in key):
        return key
    return _scalar(key)


def _scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, str):
        return _quote(value)
    raise TypeError(f"unsupported YAML value type: {type(value)!r}")


def _quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'
