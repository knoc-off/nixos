#!/usr/bin/env bash
# End-to-end check of marki as an Anki sync client, against a real
# anki-sync-server and a second client (a "phone", driven by Anki's own
# library) sharing one account:
#   1. no server reachable: push fails at pull and writes nothing;
#   2. the first push downloads the server's collection (the phone's note
#      survives), adds the cards and uploads them; the phone receives notes
#      and media, and status is clean;
#   3. the phone reviews a card; a later push that adds a card type (a
#      schema change, so a full upload) pulls first and keeps the review;
#   4. a plan that changed between simulate and confirm is refused;
#   5. a deleted card (delete_orphans / --prune) and its unused media file
#      disappear from the phone.
#
# Usage: tests/e2e-server.sh [path/to/marki]   (defaults to target/debug/marki)
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
marki=${1:-$here/target/debug/marki}
anki_lib=$(nix build --no-link --print-out-paths 'nixpkgs#anki^lib')
server_bin=$(nix build --no-link --print-out-paths 'nixpkgs#anki-sync-server')/bin/anki-sync-server
python=$(nix build --no-link --print-out-paths 'nixpkgs#python313')/bin/python3
site=$(echo "$anki_lib"/lib/python3*/site-packages)
py() { PYTHONNOUSERSITE=true PYTHONPATH="$site" "$python" - "$@"; }

w=$(mktemp -d)
port=$((20000 + RANDOM % 20000))
trap '[ -n "${spid:-}" ] && kill "$spid" 2>/dev/null; rm -rf "$w"' EXIT
fail() { echo "FAIL: $*"; exit 1; }

printf '#!/bin/sh\nPYTHONNOUSERSITE=true PYTHONPATH=%s exec %s "$@"\n' "$site" "$python" >"$w/anki-python"
chmod +x "$w/anki-python"
export MARKI_PYTHON="$w/anki-python"
echo p >"$w/pw"

# The phone: sync, then run one action on its collection.
phone() {
  py "$w" "$port" "$@" <<'EOF'
import sys, os, time
from anki.collection import Collection
w, port, action = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(f"{w}/phone", exist_ok=True)
col = Collection(f"{w}/phone/collection.anki2")

def sync():
    auth = col.sync_login("u", "p", f"http://127.0.0.1:{port}/")
    out = col.sync_collection(auth, False)
    if out.required in (out.FULL_UPLOAD, out.FULL_SYNC, out.FULL_DOWNLOAD):
        col.close_for_full_sync()
        col.full_upload_or_download(auth=auth, server_usn=out.server_media_usn,
                                    upload=out.required == out.FULL_UPLOAD)
        col.reopen(after_full_sync=True)
    col.sync_media(auth)
    while col.media_sync_status().active:
        time.sleep(0.05)

sync()
if action == "add":
    n = col.new_note(col.models.by_name("Basic"))
    n["Front"] = "from the phone"
    col.add_note(n, 1)
    sync()
elif action == "review":
    # Answer every marki card once (Good), like a study session.
    for cid in col.find_cards("tag:marki"):
        c = col.get_card(cid)
        c.start_timer()
        col.sched.answerCard(c, 3)
    sync()
elif action == "check":
    print("notes", col.note_count())
    print("marki", len(col.find_notes("tag:marki")))
    print("revlog", col.db.scalar("select count() from revlog"))
    print("types", " ".join(sorted(t["name"] for t in col.models.by_name("marki:duo")["tmpls"]))
          if col.models.by_name("marki:duo") else "types -")
    media = sorted(m for m in os.listdir(col.media.dir()) if m.startswith("marki-"))
    print("media", " ".join(media))
col.close()
EOF
}

mkdir "$w/p" && cd "$w/p"
git init -q . && git config user.email t@t && git config user.name t
"$marki" init >/dev/null 2>&1
cat >>.marki/config.toml <<EOF
collection = "$w/marki/collection.anki2"
[sync]
endpoint = "http://127.0.0.1:$port/"
username = "u"
password_file = "$w/pw"
EOF
cat >.marki/models/duo.lua <<'EOF'
local M = {}
function M.card_names() return { "Ask" } end
function M.generate(note, ctx)
  return { AskFront = note:heading(1):text(), AskBack = ctx:section_html(note, 2) }
end
return M
EOF
mkdir -p .marki/media/icons deck
printf '<svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>\n' >.marki/media/icons/dot.svg
printf 'What is this?\n\n```media\nsrc = "icons/dot"\n```\n\n---\n\nA dot\n' >deck/dot.md
printf '# Largest ocean?\n\n---\n\nPacific\n\n#model(duo)\n' >deck/ocean.md
"$marki" fmt >/dev/null
git add -A && git commit -qm init

# 1. Server down.
out=$("$marki" push 2>&1) && fail "push without a server should fail: $out"
grep -q "127.0.0.1:$port" <<<"$out" || fail "error should name the endpoint: $out"
[ ! -e "$w/marki/collection.anki2" ] || fail "a failed pull left a collection behind"
echo "ok: server down"

SYNC_USER1=u:p SYNC_BASE="$w/base" SYNC_HOST=127.0.0.1 SYNC_PORT=$port "$server_bin" >"$w/server.log" 2>&1 &
spid=$!
for _ in $(seq 100); do curl -s "127.0.0.1:$port/" >/dev/null && break; sleep 0.05; done
phone add >/dev/null

# 2. First push.
"$marki" push >"$w/push.log" 2>&1 || fail "push: $(cat "$w/push.log")"
grep -q 'pull ok: download' "$w/push.log" || fail "first pull should download: $(cat "$w/push.log")"
res=$(phone check)
grep -q '^notes 3$' <<<"$res" || fail "phone should have its note plus marki's two: $res"
grep -q '^media marki-media-' <<<"$res" || fail "phone did not get the media: $res"
st=$("$marki" status 2>&1)
grep -qE '^(add|update|media|model) ' <<<"$st" && fail "status not clean after push: $st"
grep -q 'last synced' <<<"$st" || fail "status should say when it last synced: $st"
echo "ok: first push"

# 3. Review on the phone, then a card type added in marki.
phone review >/dev/null
sed -i 's/{ "Ask" }/{ "Ask", "Reverse" }/; s/AskBack = ctx:section_html(note, 2)/AskBack = ctx:section_html(note, 2), ReverseFront = ctx:section_html(note, 2), ReverseBack = note:heading(1):text()/' .marki/models/duo.lua
"$marki" push >"$w/push.log" 2>&1 || fail "schema push: $(cat "$w/push.log")"
grep -q 'sync ok: upload' "$w/push.log" || fail "a card type change should full-upload: $(cat "$w/push.log")"
res=$(phone check)
grep -q '^types Ask Reverse$' <<<"$res" || fail "phone should have the new card type: $res"
grep -q '^revlog 2$' <<<"$res" || fail "the phone's reviews must survive the full upload: $res"
echo "ok: schema change keeps phone reviews"

# 4 and 5 through the MCP tools: a stale plan hash is refused, then a
# confirmed delete_orphans push deletes the note and its media everywhere.
mport=$((port + 1))
"$marki" mcp --listen "127.0.0.1:$mport" >"$w/mcp.log" 2>&1 &
mpid=$!
trap '[ -n "${spid:-}" ] && kill "$spid" 2>/dev/null; kill "$mpid" 2>/dev/null; rm -rf "$w"' EXIT
for _ in $(seq 50); do curl -s "127.0.0.1:$mport/mcp" >/dev/null && break; sleep 0.1; done
git rm -q deck/dot.md && git commit -qm "drop dot"
py "$mport" <<'EOF' || fail "mcp steps"
import json, sys, urllib.request
url = f"http://127.0.0.1:{sys.argv[1]}/mcp"
H = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
def rpc(method, params, sid=None, id=1):
    h = dict(H, **({"mcp-session-id": sid} if sid else {}))
    body = {"jsonrpc": "2.0", "method": method, "params": params}
    if id is not None: body["id"] = id
    r = urllib.request.urlopen(urllib.request.Request(url, json.dumps(body).encode(), h))
    data = [l[5:] for l in r.read().decode().splitlines() if l.startswith("data:") and l[5:].strip()]
    return r.headers.get("mcp-session-id"), json.loads(data[-1]) if data else None
sid, _ = rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}, "clientInfo": {"name": "t", "version": "0"}})
rpc("notifications/initialized", {}, sid, id=None)
def tool(name, args):
    _, r = rpc("tools/call", {"name": name, "arguments": args}, sid)
    r = r["result"]
    text = r["content"][0]["text"]
    return (json.loads(text) if not r.get("isError") else None), text
sim, _ = tool("marki_push", {"delete_orphans": True})
assert sim and sim["summary"] == {"orphan": 1, "media_delete": 1}, sim
_, err = tool("marki_push", {"confirm": True, "plan_hash": "0000", "delete_orphans": True})
assert "plan changed" in err, err
done, text = tool("marki_push", {"confirm": True, "plan_hash": sim["plan_hash"], "delete_orphans": True})
assert done and done["ok"], text
steps = {s["name"]: s["status"] for s in done["steps"]}
assert steps == {"pull": "ok", "media": "ok", "collection": "ok", "media cleanup": "ok", "sync": "ok", "git": "ok"}, steps
EOF
res=$(phone check)
grep -q '^marki 1$' <<<"$res" || fail "the deleted note should be gone from the phone: $res"
grep -q '^media $' <<<"$res" || fail "the unused media file should be gone from the phone: $res"
echo "ok: stale plan refused; deletion reaches the phone"

echo "all server e2e checks passed"
