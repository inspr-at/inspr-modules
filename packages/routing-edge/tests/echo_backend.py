"""Loopback echo/SSE origin used only by isolated Traefik process tests."""

from __future__ import annotations

import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlsplit


class EchoState:
    def __init__(self, app_id: str, sse_hold: float = 0.4) -> None:
        self.app_id = app_id
        self.sse_hold = sse_hold
        self.requests: list[dict[str, Any]] = []
        self.lock = threading.Lock()


def _is_sse(path: str) -> bool:
    return path.endswith("/stream") or path.endswith("/changes") or path.endswith("/events")


class EchoHandler(BaseHTTPRequestHandler):
    server: "EchoServer"

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A003
        return

    def _record(self) -> dict[str, Any]:
        parsed = urlsplit(self.path)
        record = {
            "app_id": self.server.state.app_id,
            "method": self.command,
            "path": parsed.path,
            "query": parsed.query,
            "host": self.headers.get("Host", ""),
            "x_forwarded_host": self.headers.get("X-Forwarded-Host", ""),
            "x_forwarded_proto": self.headers.get("X-Forwarded-Proto", ""),
            "x_forwarded_prefix": self.headers.get("X-Forwarded-Prefix", ""),
            "x_forwarded_user": self.headers.get("X-Forwarded-User"),
            "x_remote_user": self.headers.get("X-Remote-User"),
            "remote_user": self.headers.get("Remote-User"),
        }
        with self.server.state.lock:
            self.server.state.requests.append(record)
        return record

    def do_GET(self) -> None:  # noqa: N802
        record = self._record()
        parsed = urlsplit(self.path)
        if _is_sse(parsed.path):
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            self.wfile.write(b"data: first\n\n")
            self.wfile.flush()
            time.sleep(self.server.state.sse_hold)
            self.wfile.write(b"data: second\n\n")
            self.wfile.flush()
            return
        body = json.dumps(record).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:  # noqa: N802
        self.do_GET()

    def do_HEAD(self) -> None:  # noqa: N802
        self._record()
        self.send_response(200)
        self.end_headers()


class EchoServer(ThreadingHTTPServer):
    def __init__(self, host: str, port: int, state: EchoState) -> None:
        super().__init__((host, port), EchoHandler)
        self.state = state


def start_echo(app_id: str, port: int, sse_hold: float = 0.4) -> tuple[EchoServer, EchoState]:
    state = EchoState(app_id, sse_hold=sse_hold)
    server = EchoServer("127.0.0.1", port, state)
    thread = threading.Thread(target=server.serve_forever, name=f"echo-{app_id}", daemon=True)
    thread.start()
    server.thread = thread  # type: ignore[attr-defined]
    return server, state
