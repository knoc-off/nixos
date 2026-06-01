#!/usr/bin/env python3
"""
host-query: Runs outside the bubblewrap jail, executes commands on the host
and returns output to the jailed opencode agent via HTTP.

The agent's tool permission is set to "ask", so the user always approves
each command in the opencode TUI before it reaches this server.
"""
import http.server
import json
import subprocess
import sys
import signal

MAX_OUTPUT = 200_000  # Truncate very large outputs
TIMEOUT = 30


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.rstrip("/") != "/exec":
            return self._json(404, {"error": "Not found. Use POST /exec"})

        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
        except (json.JSONDecodeError, ValueError):
            return self._json(400, {"error": "Invalid JSON body"})

        command = body.get("command", "").strip()
        if not command:
            return self._json(400, {"error": "Missing 'command' field"})

        try:
            result = subprocess.run(
                command, shell=True, capture_output=True, text=True, timeout=TIMEOUT
            )
            output = result.stdout
            if result.stderr:
                output += "\n--- stderr ---\n" + result.stderr
            if len(output) > MAX_OUTPUT:
                output = output[:MAX_OUTPUT] + f"\n... (truncated at {MAX_OUTPUT} bytes)"
            self._json(200, {
                "command": command,
                "exit_code": result.returncode,
                "output": output,
            })
        except subprocess.TimeoutExpired:
            self._json(504, {"error": f"Timed out after {TIMEOUT}s", "command": command})
        except Exception as e:
            self._json(500, {"error": str(e), "command": command})

    def do_GET(self):
        if self.path.rstrip("/") == "/health":
            return self._json(200, {"status": "ok"})
        self._json(404, {"error": "Use POST /exec or GET /health"})

    def _json(self, status, data):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 19600
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    srv = http.server.HTTPServer(("127.0.0.1", port), Handler)
    print(f"host-query: listening on 127.0.0.1:{port}", flush=True)
    srv.serve_forever()
