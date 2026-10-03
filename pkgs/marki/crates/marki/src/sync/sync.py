# Sync marki's local collection with an Anki sync server, using Anki's own
# library so the protocol is exactly Anki's. Run by marki (sync/client.rs)
# with one JSON request as argv[1]; prints one JSON result line on stdout.
# Errors go to stderr with a non-zero exit.
#
# Request: {"collection", "endpoint", "username", "password_file",
#           "mode": "pull" | "push", "allow_upload": bool}
#
# Full syncs (a one-way copy of the whole collection) never guess:
# - FULL_UPLOAD means the server is empty: upload.
# - FULL_DOWNLOAD means our copy is empty: download.
# - FULL_SYNC (schemas differ) on "pull", before marki writes anything:
#   download. The local copy holds nothing that marki can't regenerate from
#   the cards repo, while the server may hold reviews.
# - FULL_SYNC on "push": upload only when this push changed the schema
#   (allow_upload), which it did seconds after pulling; otherwise fail.
import json
import sys
import time

from anki.collection import Collection

MEDIA_TIMEOUT_SECS = 30 * 60

req = json.loads(sys.argv[1])
with open(req["password_file"]) as f:
    password = f.read().strip()

col = Collection(req["collection"])
try:
    auth = col.sync_login(req["username"], password, req["endpoint"])
    out = col.sync_collection(auth, False)
    # After an incremental sync pylib reports NO_CHANGES whether or not rows
    # moved, so "normal" covers both.
    action = "normal"
    if out.required in (out.FULL_UPLOAD, out.FULL_DOWNLOAD, out.FULL_SYNC):
        if out.required == out.FULL_UPLOAD:
            upload = True
        elif out.required == out.FULL_DOWNLOAD:
            upload = False
        elif req["mode"] == "pull":
            upload = False
        elif req.get("allow_upload"):
            upload = True
        else:
            sys.exit(
                "the server asks for a full sync, but this push did not change a "
                "card type; another device changed the collection's schema. Push "
                "again: the pull will download the server's copy first."
            )
        col.close_for_full_sync()
        col.full_upload_or_download(
            auth=auth, server_usn=out.server_media_usn, upload=upload
        )
        col.reopen(after_full_sync=True)
        action = "upload" if upload else "download"

    col.sync_media(auth)
    deadline = time.monotonic() + MEDIA_TIMEOUT_SECS
    # Raises if the media sync failed.
    while col.media_sync_status().active:
        if time.monotonic() > deadline:
            col.abort_media_sync()
            sys.exit(f"media sync still running after {MEDIA_TIMEOUT_SECS}s")
        time.sleep(0.1)
    if out.server_message:
        print(f"server: {out.server_message}", file=sys.stderr)
finally:
    col.close()

print(json.dumps({"action": action}))
