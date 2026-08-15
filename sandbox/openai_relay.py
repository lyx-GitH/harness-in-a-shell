#!/usr/bin/env python3

import hashlib
import http.client
import json
import os
import socketserver
import ssl
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Optional


UPSTREAM_HOST = "api.openai.com"
UPSTREAM_PATH = "/v1/responses"
SOCKET_PATH = os.environ.get(
    "OPENAI_RELAY_SOCKET", "/run/openai-relay/openai.sock"
)
REQUEST_COUNT_PATH = "/tmp/openai-request-count"
PAUSE_READY_PATH = "/tmp/openai-pause-ready"
PAUSE_RELEASE_PATH = "/tmp/openai-pause-release"
PAUSE_INPUT_PATH = "/tmp/openai-pause-input"
PAUSE_INPUT_SHA256_PATH = "/tmp/openai-pause-input-sha256"


def positive_int(name: str, default: int) -> int:
    value = int(os.environ.get(name, str(default)))
    if value <= 0:
        raise ValueError(f"{name} must be positive")
    return value


def optional_positive_int(name: str) -> Optional[int]:
    raw_value = os.environ.get(name, "")
    if not raw_value:
        return None
    value = int(raw_value)
    if value <= 0:
        raise ValueError(f"{name} must be positive when set")
    return value


API_KEY = os.environ["OPENAI_API_KEY"]
ALLOWED_MODEL = os.environ.get("OPENAI_ALLOWED_MODEL", "gpt-5.6-sol")
REASONING_EFFORT = os.environ.get("OPENAI_REASONING_EFFORT", "")
ALLOWED_REASONING_EFFORTS = {
    "",
    "none",
    "low",
    "medium",
    "high",
    "xhigh",
    "max",
}
if REASONING_EFFORT not in ALLOWED_REASONING_EFFORTS:
    raise ValueError("OPENAI_REASONING_EFFORT is invalid")
MAX_REQUESTS = positive_int("OPENAI_MAX_REQUESTS", 8)
PAUSE_AFTER_REQUESTS = int(os.environ.get("OPENAI_PAUSE_AFTER_REQUESTS") or "0")
if PAUSE_AFTER_REQUESTS < 0 or PAUSE_AFTER_REQUESTS >= MAX_REQUESTS:
    raise ValueError(
        "OPENAI_PAUSE_AFTER_REQUESTS must be zero or less than OPENAI_MAX_REQUESTS"
    )
MAX_BODY_BYTES = positive_int("OPENAI_MAX_BODY_BYTES", 512 * 1024)
MAX_OUTPUT_TOKENS = optional_positive_int("OPENAI_MAX_OUTPUT_TOKENS")
MAX_RESPONSE_BYTES = positive_int("OPENAI_MAX_RESPONSE_BYTES", 32 * 1024 * 1024)
UPSTREAM_TIMEOUT_SECONDS = positive_int("OPENAI_UPSTREAM_TIMEOUT_SECONDS", 180)
CLIENT_TIMEOUT_SECONDS = positive_int("OPENAI_CLIENT_TIMEOUT_SECONDS", 10)
SSL_CONTEXT = ssl.create_default_context()


def store_request_count(value: int) -> None:
    temporary_path = REQUEST_COUNT_PATH + ".tmp"
    with open(temporary_path, "w", encoding="ascii") as count_file:
        count_file.write(f"{value}\n")
    os.replace(temporary_path, REQUEST_COUNT_PATH)


class DuplicateKeyError(ValueError):
    pass


def strict_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKeyError(key)
        result[key] = value
    return result


class RelayHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "react-openai-relay/1"
    request_count = 0
    pause_completed = False

    def setup(self) -> None:
        super().setup()
        self.connection.settimeout(CLIENT_TIMEOUT_SECONDS)

    def log_message(self, format_string: str, *args: object) -> None:
        # The client is arbitrary Bash. Do not give invalid-request floods an
        # attacker-controlled Docker log channel.
        return

    def reply(self, status: int, message: str) -> None:
        body = json.dumps(
            {"error": {"type": "sandbox_relay_error", "message": message}},
            separators=(",", ":"),
        ).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def wait_for_checkpoint_release(self, input_text: str) -> None:
        if not (
            PAUSE_AFTER_REQUESTS
            and RelayHandler.request_count == PAUSE_AFTER_REQUESTS
            and not RelayHandler.pause_completed
        ):
            return

        input_bytes = input_text.encode("utf-8")
        temporary_input_path = PAUSE_INPUT_PATH + ".tmp"
        with open(temporary_input_path, "wb") as input_file:
            input_file.write(input_bytes)
        os.replace(temporary_input_path, PAUSE_INPUT_PATH)

        input_hash = hashlib.sha256(input_bytes).hexdigest()
        temporary_hash_path = PAUSE_INPUT_SHA256_PATH + ".tmp"
        with open(temporary_hash_path, "w", encoding="ascii") as hash_file:
            hash_file.write(f"{input_hash}\n")
        os.replace(temporary_hash_path, PAUSE_INPUT_SHA256_PATH)

        temporary_path = PAUSE_READY_PATH + ".tmp"
        with open(temporary_path, "w", encoding="ascii") as ready_file:
            ready_file.write(f"{RelayHandler.request_count}\n")
        os.replace(temporary_path, PAUSE_READY_PATH)
        while not os.path.exists(PAUSE_RELEASE_PATH):
            time.sleep(0.1)
        os.unlink(PAUSE_RELEASE_PATH)
        os.unlink(PAUSE_READY_PATH)
        RelayHandler.pause_completed = True

    def do_GET(self) -> None:
        if self.path != "/healthz":
            self.reply(404, "route not allowed")
            return
        body = b"ok\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self) -> None:
        if self.path != UPSTREAM_PATH:
            self.reply(404, "only POST /v1/responses is allowed")
            return
        if self.headers.get("Transfer-Encoding"):
            self.reply(400, "transfer-encoded requests are not accepted")
            return

        content_lengths = self.headers.get_all("Content-Length", [])
        if len(content_lengths) != 1:
            self.reply(411, "exactly one Content-Length is required")
            return
        if self.headers.get_content_type() != "application/json":
            self.reply(415, "Content-Type must be application/json")
            return

        try:
            content_length = int(content_lengths[0])
        except ValueError:
            self.reply(411, "a valid Content-Length is required")
            return
        if content_length <= 0 or content_length > MAX_BODY_BYTES:
            self.reply(413, "request body is empty or too large")
            return

        try:
            raw_body = self.rfile.read(content_length)
        except (OSError, TimeoutError):
            self.reply(408, "request body timed out")
            return
        try:
            request = json.loads(raw_body, object_pairs_hook=strict_object)
        except (
            UnicodeDecodeError,
            json.JSONDecodeError,
            DuplicateKeyError,
            RecursionError,
        ):
            self.reply(400, "request body must be valid JSON")
            return
        if not isinstance(request, dict):
            self.reply(400, "request body must be a JSON object")
            return
        if set(request) != {"model", "instructions", "input"}:
            self.reply(400, "only model, instructions, and input are accepted")
            return
        if not all(isinstance(request[field], str) for field in request):
            self.reply(400, "model, instructions, and input must be strings")
            return
        if request["model"] != ALLOWED_MODEL:
            self.reply(403, f"only model {ALLOWED_MODEL!r} is allowed")
            return

        self.wait_for_checkpoint_release(request["input"])

        if RelayHandler.request_count >= MAX_REQUESTS:
            self.reply(429, "sandbox request limit reached")
            return
        RelayHandler.request_count += 1
        store_request_count(RelayHandler.request_count)

        upstream_request = {
            "model": request["model"],
            "instructions": request["instructions"],
            "input": request["input"],
            "store": False,
            "stream": False,
        }
        if MAX_OUTPUT_TOKENS is not None:
            upstream_request["max_output_tokens"] = MAX_OUTPUT_TOKENS
        if REASONING_EFFORT:
            upstream_request["reasoning"] = {"effort": REASONING_EFFORT}
        upstream_body = json.dumps(upstream_request, separators=(",", ":")).encode(
            "utf-8"
        )
        headers = {
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
            "User-Agent": "harness-in-a-shell-relay/1",
        }
        if os.environ.get("OPENAI_ORGANIZATION"):
            headers["OpenAI-Organization"] = os.environ["OPENAI_ORGANIZATION"]
        if os.environ.get("OPENAI_PROJECT"):
            headers["OpenAI-Project"] = os.environ["OPENAI_PROJECT"]

        connection = http.client.HTTPSConnection(
            UPSTREAM_HOST,
            443,
            timeout=UPSTREAM_TIMEOUT_SECONDS,
            context=SSL_CONTEXT,
        )
        try:
            connection.request("POST", UPSTREAM_PATH, body=upstream_body, headers=headers)
            upstream = connection.getresponse()
            response_body = upstream.read(MAX_RESPONSE_BYTES + 1)
            if len(response_body) > MAX_RESPONSE_BYTES:
                self.reply(502, "upstream response exceeded the sandbox limit")
                return

            self.send_response(upstream.status, upstream.reason)
            content_type = upstream.getheader("Content-Type")
            if content_type:
                self.send_header("Content-Type", content_type)
            for header, value in upstream.getheaders():
                lowered = header.lower()
                if lowered == "x-request-id" or lowered.startswith("x-ratelimit-"):
                    self.send_header(header, value)
            self.send_header("Content-Length", str(len(response_body)))
            self.end_headers()
            self.wfile.write(response_body)
        except (OSError, http.client.HTTPException) as error:
            self.reply(502, f"OpenAI upstream request failed: {type(error).__name__}")
        finally:
            connection.close()

    def do_CONNECT(self) -> None:
        self.reply(405, "CONNECT is not allowed")

    def do_PUT(self) -> None:
        self.reply(405, "method not allowed")

    def do_DELETE(self) -> None:
        self.reply(405, "method not allowed")

    def do_PATCH(self) -> None:
        self.reply(405, "method not allowed")


class UnixHTTPServer(socketserver.UnixStreamServer, HTTPServer):
    def server_bind(self) -> None:
        socketserver.UnixStreamServer.server_bind(self)
        self.server_name = "openai-relay"
        self.server_port = 0


if __name__ == "__main__":
    try:
        os.unlink(SOCKET_PATH)
    except FileNotFoundError:
        pass
    store_request_count(0)
    server = UnixHTTPServer(SOCKET_PATH, RelayHandler)
    os.chmod(SOCKET_PATH, 0o600)
    server.serve_forever()
