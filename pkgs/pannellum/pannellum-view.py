#!/usr/bin/env python3
"""Quickly view a panorama/equirectangular image with Pannellum in your browser."""
import http.server
import os
import sys
import tempfile
import threading
import urllib.parse
import webbrowser


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: pannellum-view <image>", file=sys.stderr)
        return 1

    image_path = os.path.realpath(sys.argv[1])
    if not os.path.isfile(image_path):
        print(f"error: no such file: {image_path}", file=sys.stderr)
        return 1

    pannellum_share = os.environ["PANNELLUM_SHARE"]

    with tempfile.TemporaryDirectory(prefix="pannellum-view-") as tmpdir:
        for name in ("pannellum.htm", "pannellum.js", "pannellum.css"):
            os.symlink(os.path.join(pannellum_share, name), os.path.join(tmpdir, name))

        image_name = os.path.basename(image_path)
        os.symlink(image_path, os.path.join(tmpdir, image_name))

        handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
            *a, directory=tmpdir, **kw
        )
        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler) as httpd:
            port = httpd.server_address[1]
            url = (
                f"http://127.0.0.1:{port}/pannellum.htm#"
                f"panorama={urllib.parse.quote(image_name)}&autoLoad=true"
            )
            threading.Thread(target=httpd.serve_forever, daemon=True).start()
            webbrowser.open(url)
            print(f"Serving {image_name} at {url} (Ctrl+C to stop)")
            try:
                threading.Event().wait()
            except KeyboardInterrupt:
                pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
