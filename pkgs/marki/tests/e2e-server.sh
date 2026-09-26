#!/usr/bin/env bash
# End-to-end check of marki against a *running* anki-sync-server, the way it
# is deployed: the server holds the collection and media.db with exclusive
# locks for as long as it runs, so marki must pause it around writes.
#
#  1. start anki-sync-server; an Anki client (pylib) creates a collection and
#     does a full upload + media sync, so the server holds both files;
#  2. read-only commands (status, check) work without stopping the server;
#  3. without [server] commands a push refuses and writes nothing;
#  4. with a stop command that fails, nothing is written and the server is
#     left running;
#  5. with working stop/start commands the push lands; the client syncs and
#     receives the notes and the media file, and status is clean afterwards;
#  6. a media failure (media dir unwritable) stops the push before the
#     collection, and status reports the pending changes.
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
export w port server_bin
server_pid=""

# The server is managed through a pidfile so the stop/start scripts marki
# runs (separate processes) can control it.
cat >"$w/start.sh" <<'EOF'
#!/usr/bin/env bash
SYNC_USER1=u:p SYNC_BASE="$w/base" SYNC_HOST=127.0.0.1 SYNC_PORT=$port \
  "$server_bin" >>"$w/server.log" 2>&1 &
echo $! >"$w/server.pid"
for _ in $(seq 100); do curl -s "127.0.0.1:$port/" >/dev/null && exit 0; sleep 0.05; done
echo "server did not come up" >&2; exit 1
EOF
cat >"$w/stop.sh" <<'EOF'
#!/usr/bin/env bash
pid=$(cat "$w/server.pid"); kill "$pid"
while kill -0 "$pid" 2>/dev/null; do sleep 0.05; done
EOF
chmod +x "$w/start.sh" "$w/stop.sh"
trap '[ -f "$w/server.pid" ] && kill $(cat "$w/server.pid") 2>/dev/null; rm -rf "$w"' EXIT
"$w/start.sh"
running() { kill -0 "$(cat "$w/server.pid")" 2>/dev/null; }

# Client: create a collection, full-upload it, sync media. Afterwards the
# server has both files open with exclusive locks.
client() {
  py "$w" "$port" "$@" <<'EOF'
import sys, os, time
from anki.collection import Collection
w, port, action = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(f"{w}/client", exist_ok=True)
col = Collection(f"{w}/client/collection.anki2")
auth = col.sync_login("u", "p", f"http://127.0.0.1:{port}/")
out = col.sync_collection(auth, True)
if out.required in (out.FULL_UPLOAD, out.FULL_SYNC, out.FULL_DOWNLOAD):
    col.close_for_full_sync()
    col.full_upload_or_download(auth=auth, server_usn=out.server_media_usn,
                                upload=(action == "upload"))
    col.reopen(after_full_sync=True)
col.sync_media(auth)
for _ in range(200):
    if not col.media_sync_status().active: break
    time.sleep(0.05)
if action == "check":
    notes = sorted(col.get_note(n).fields[0] for n in col.find_notes("tag:marki"))
    print("notes", len(notes))
    media = sorted(os.listdir(col.media.dir()))
    print("media", " ".join(m for m in media if m.startswith("marki-")))
col.close()
EOF
}
client upload >/dev/null

lockers() { ls -l /proc/"$(cat "$w/server.pid")"/fd 2>/dev/null | grep -cE 'collection.anki2$|media.db$' || true; }
[ "$(lockers)" = 2 ] || { echo "FAIL: server does not hold both dbs"; exit 1; }

mkdir "$w/p" && cd "$w/p"
git init -q . && git config user.email t@t && git config user.name t
"$marki" init >/dev/null 2>&1
echo "collection = \"$w/base/u/collection.anki2\"" >>.marki/config.toml
mkdir -p .marki/media/icons deck
printf '<svg xmlns="http://www.w3.org/2000/svg"><circle r="1"/></svg>\n' >.marki/media/icons/dot.svg
printf 'What is this?\n\n```media\nsrc = "icons/dot"\n```\n\n---\n\nA dot\n' >deck/dot.md
printf 'Largest ocean?\n\n---\n\nPacific\n' >deck/ocean.md
"$marki" fmt >/dev/null
git add -A && git commit -qm init

fail() { echo "FAIL: $*"; exit 1; }
notes() { python3 -c "import sqlite3,sys; print(sqlite3.connect(sys.argv[1]).execute('select count() from notes').fetchone()[0])" "$1"; }

# 2. Reads work while the server runs.
st=$("$marki" status 2>&1) || fail "status: $st"
grep -q 'snapshot' <<<"$st" || fail "status should say it read a snapshot: $st"
grep -q '^media ' <<<"$st" || fail "status should list the media file: $st"
[ "$(grep -c '^add ' <<<"$st")" = 2 ] || fail "status should plan 2 adds: $st"
"$marki" push --simulate >/dev/null 2>"$w/sim.err" && fail "simulate should flag the missing [server] commands"
grep -q 'no \[server\]' "$w/sim.err" || fail "simulate problem: $(cat "$w/sim.err")"
running || fail "reads stopped the server"

# 3. No [server]: refuse, write nothing.
out=$("$marki" push 2>&1) && fail "push without [server] should fail: $out"
grep -q 'locked by another process' <<<"$out" || fail "unexpected: $out"
running || fail "server died"

# 4. A failing stop command: nothing written, server untouched.
cp .marki/config.toml "$w/config.base"
{ cat "$w/config.base"; printf '[server]\nstop = ["false"]\nstart = ["%s"]\n' "$w/start.sh"; } >.marki/config.toml
out=$("$marki" push 2>&1) && fail "push with failing stop should fail: $out"
grep -q 'stop server' <<<"$out" || fail "unexpected: $out"
running || fail "server died"

# 6 (before 5, so the collection is still empty). Unwritable media dir:
# media step fails, collection is skipped, server comes back.
{ cat "$w/config.base"; printf '[server]\nstop = ["%s"]\nstart = ["%s"]\n' "$w/stop.sh" "$w/start.sh"; } >.marki/config.toml
chmod 0500 "$w/base/u/media"
out=$("$marki" push 2>&1) && fail "push with unwritable media should fail: $out"
grep -q 'media step failed' <<<"$out" || fail "unexpected: $out"
grep -q 'collection skipped' <<<"$out" || fail "collection should be skipped: $out"
chmod 0700 "$w/base/u/media"
running || fail "server not restarted after a failed push"
"$w/stop.sh"
[ "$(notes "$w/base/u/collection.anki2")" = 0 ] || fail "collection written despite media failure"
"$w/start.sh"

# 5. The real thing.
"$marki" push >"$w/push.log" 2>&1 || fail "push: $(cat "$w/push.log")"
running || fail "server not restarted"
st=$("$marki" status 2>&1)
grep -qE '^(add|update|media|model) ' <<<"$st" && fail "status not clean after push: $st"
res=$(client check)
grep -q '^notes 2$' <<<"$res" || fail "client did not get the notes: $res"
grep -q '^media marki-media-' <<<"$res" || fail "client did not get the media: $res"
echo "all server e2e checks passed"
