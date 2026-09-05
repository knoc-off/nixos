#!/usr/bin/env python3
"""
host-query: Runs outside the bubblewrap jail, executes commands on the host
and returns output to the jailed opencode agent via HTTP.

The agent's tool permission is set to "ask", so the user always approves
each command in the opencode TUI before it reaches this server.

Usage: host-query <port> [grant-root]
  grant-root enables POST /mount (read-only host directory grants).
"""
import http.server
import json
import os
import re
import subprocess
import sys
import signal

MAX_OUTPUT = 200_000  # Truncate very large outputs
TIMEOUT = 30

# Where read-only grants are mounted. Set from argv[2]; when absent the
# /mount endpoint is disabled. This is the *host-side* backing dir of the
# jail's ~/scratch, so mounts made here propagate into the running jail.
GRANT_ROOT = None
GRANT_JAIL_PREFIX = "~/scratch/granted"

# Mount names must start alphanumeric: a leading dot would hide the grant from
# the session-exit cleanup glob, leaking the mount past the jail's lifetime.
SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        path = self.path.rstrip("/")
        if path == "/mount":
            return self._mount()
        if path != "/exec":
            return self._json(404, {"error": "Not found. Use POST /exec or /mount"})

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

    def _mount(self):
        """Bind a host directory read-only into the jail's ~/scratch/granted.

        bindfs rather than `mount --bind` because this runs as the unprivileged
        user: fusermount3 is setuid so FUSE mounts need no root, and bindfs
        gives `-o ro` natively. --no-allow-other is required because
        user_allow_other is not set in /etc/fuse.conf.

        The mount lands under the host-side backing dir of the jail's
        ~/scratch, which is a propagation slave of the host's /home -- so it
        appears inside the *running* jail with no restart.
        """
        if not GRANT_ROOT:
            return self._json(503, {"error": "Mount grants disabled (no grant root)"})

        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length)) if length else {}
        except (json.JSONDecodeError, ValueError):
            return self._json(400, {"error": "Invalid JSON body"})

        src = os.path.realpath(os.path.expanduser(body.get("path", "").strip()))
        if not src or not os.path.isdir(src):
            return self._json(400, {"error": f"Not a directory: {src or '(empty)'}"})

        # Leading dots stripped so granting e.g. ~/.ssh defaults to "ssh"
        # rather than being rejected by SAFE_NAME.
        name = (body.get("name") or os.path.basename(src)).strip().lstrip(".")
        if not SAFE_NAME.match(name):
            return self._json(400, {"error": f"Invalid mount name: {name!r}"})

        target = os.path.join(GRANT_ROOT, name)
        # os.path.ismount is the check that matters: a leftover empty dir from a
        # previous grant is fine to reuse, an active mount is not.
        if os.path.ismount(target):
            return self._json(409, {"error": f"Already mounted: {name}"})

        try:
            os.makedirs(target, exist_ok=True)
            r = subprocess.run(
                ["bindfs", "--no-allow-other", "-o", "ro", src, target],
                capture_output=True, text=True, timeout=TIMEOUT,
            )
        except Exception as e:
            return self._json(500, {"error": str(e)})

        if r.returncode != 0:
            if not os.listdir(target):
                os.rmdir(target)
            return self._json(500, {"error": (r.stderr or r.stdout).strip()})

        self._json(200, {
            "source": src,
            "jail_path": f"{GRANT_JAIL_PREFIX}/{name}",
            "mode": "ro",
        })

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
    if len(sys.argv) > 2:
        GRANT_ROOT = sys.argv[2]
        os.makedirs(GRANT_ROOT, exist_ok=True)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    srv = http.server.HTTPServer(("127.0.0.1", port), Handler)
    print(f"host-query: listening on 127.0.0.1:{port}", flush=True)
    srv.serve_forever()
