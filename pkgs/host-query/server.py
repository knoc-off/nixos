#!/usr/bin/env python3
"""
host-query: Runs outside the bubblewrap jail, executes commands on the host
and returns output to the jailed opencode agent via HTTP.

The agent's tool permission is set to "ask", so the user always approves
each command in the opencode TUI before it reaches this server.

Usage: host-query <port> [grant-root]
  grant-root enables POST /mount (host directory grants, ro unless write).

Commands run in their own session (no controlling terminal), so a password
prompt can never leak into the TUI. Set HOST_QUERY_ASKPASS to a GUI askpass
helper to make sudo prompt in a window instead of failing.
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
# Commands get their own, much longer budget: a sudo askpass prompt blocks on a
# human, and 30s is not enough time to notice a dialog and touch the reader.
# Mount operations keep TIMEOUT -- they never wait on a person.
EXEC_TIMEOUT = 120

# GUI password prompt for sudo, injected by the Nix wrapper. sudo falls back to
# an askpass helper on its own whenever no terminal is available (no -A needed),
# which is exactly the case below thanks to start_new_session. Absent outside
# Nix, where sudo then just fails with "a terminal is required" -- still no hang.
ASKPASS = os.environ.get("HOST_QUERY_ASKPASS")

# Where grants are mounted. Set from argv[2]; when absent the /mount endpoint
# is disabled. This is the *host-side* backing dir of the jail's ~/scratch, so
# mounts made here propagate into the running jail.
GRANT_ROOT = None
GRANT_JAIL_PREFIX = "~/scratch/granted"

# name -> (source, write). Lets a repeat grant tell "same thing again" (no-op)
# from "same name, different source or mode" (remount) without shelling out to
# parse /proc/mounts. The grant root is per-session and swept at jail startup,
# so this process's view is authoritative for its own lifetime.
MOUNTS = {}

# The *setuid* fusermount3 from /run/wrappers: the store one lacks the
# privilege to unmount and fails with EPERM.
FUSERMOUNT = "/run/wrappers/bin/fusermount3"

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
                command,
                shell=True,
                capture_output=True,
                text=True,
                timeout=EXEC_TIMEOUT,
                # Detach into a new session, severing the controlling terminal.
                # Without this the child inherits the *opencode TUI's* tty (the
                # launcher backgrounds this server from the same shell), and
                # anything that reads a password -- sudo, ssh, git -- opens
                # /dev/tty directly, bypassing the pipes above: the prompt is
                # drawn into the TUI, echo goes off, and the agent's keystrokes
                # are swallowed until the timeout. With no tty, sudo instead
                # uses SUDO_ASKPASS (a GUI dialog), or fails fast and legibly.
                start_new_session=True,
                env={**os.environ, **({"SUDO_ASKPASS": ASKPASS} if ASKPASS else {})},
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
            self._json(504, {"error": f"Timed out after {EXEC_TIMEOUT}s", "command": command})
        except Exception as e:
            self._json(500, {"error": str(e), "command": command})

    def _mount(self):
        """Bind a host directory into the jail's ~/scratch/granted.

        Read-only by default; `"write": true` drops the `-o ro`. Granting a
        name that is already mounted remounts it rather than erroring, so
        re-granting a read-only dir as writable needs no explicit unmount.

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
        write = bool(body.get("write"))
        # A leftover empty dir from a previous grant is fine to reuse; an
        # active mount is not. Rather than making the agent unmount by hand,
        # remount in place: identical requests are a no-op, and a changed
        # source or mode (typically ro -> rw) just works.
        if os.path.ismount(target):
            if MOUNTS.get(name) == (src, write):
                return self._json(200, {
                    "source": src,
                    "jail_path": f"{GRANT_JAIL_PREFIX}/{name}",
                    "mode": "rw" if write else "ro",
                    "remounted": False,
                })
            u = subprocess.run(
                [FUSERMOUNT, "-u", target],
                capture_output=True, text=True, timeout=TIMEOUT,
            )
            if u.returncode != 0:
                return self._json(409, {
                    "error": f"Already mounted and could not unmount {name}: "
                             f"{(u.stderr or u.stdout).strip()}"
                })
            MOUNTS.pop(name, None)
            remounted = True
        else:
            remounted = False

        try:
            os.makedirs(target, exist_ok=True)
            r = subprocess.run(
                ["bindfs", "--no-allow-other"]
                + ([] if write else ["-o", "ro"])
                + [src, target],
                capture_output=True, text=True, timeout=TIMEOUT,
            )
        except Exception as e:
            return self._json(500, {"error": str(e)})

        if r.returncode != 0:
            if not os.listdir(target):
                os.rmdir(target)
            return self._json(500, {"error": (r.stderr or r.stdout).strip()})

        MOUNTS[name] = (src, write)
        self._json(200, {
            "source": src,
            "jail_path": f"{GRANT_JAIL_PREFIX}/{name}",
            "mode": "rw" if write else "ro",
            "remounted": remounted,
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
