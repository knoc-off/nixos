#!/usr/bin/env bash
# End-to-end check of `marki mcp` over real HTTP: starts the server on a
# fresh Anki-created collection and drives every tool through JSON-RPC,
# then has Anki's own library confirm the pushed result.
#
# Usage: tests/e2e-mcp.sh [path/to/marki]   (defaults to target/debug/marki)
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
marki=${1:-$here/target/debug/marki}
anki_lib=$(nix build --no-link --print-out-paths 'nixpkgs#anki^lib')
python=$(nix build --no-link --print-out-paths 'nixpkgs#python313')/bin/python3
site=$(echo "$anki_lib"/lib/python3*/site-packages)
py() { PYTHONNOUSERSITE=true PYTHONPATH="$site" "$python" - "$@"; }

w=$(mktemp -d)
mkdir "$w/p"
cd "$w/p"
git init -q . && git config user.email t@t && git config user.name t

py "$w/col.anki2" <<'EOF'
import sys
from anki.collection import Collection
Collection(sys.argv[1]).close()
EOF
"$marki" init >/dev/null 2>&1
echo "collection = \"$w/col.anki2\"" >>.marki/config.toml
git add -A && git commit -qm init

port=$((20000 + RANDOM % 20000))
"$marki" mcp --listen "127.0.0.1:$port" >"$w/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null; rm -rf "$w"' EXIT
for _ in $(seq 50); do curl -s "127.0.0.1:$port/mcp" >/dev/null && break; sleep 0.1; done

# The client half lives in python (json handling); it asserts as it goes.
py "$port" "$w" <<'EOF'
import sys, json, urllib.request, sqlite3
port, w = sys.argv[1], sys.argv[2]
url = f"http://127.0.0.1:{port}/mcp"
sid = None
n = 0

def rpc(method, params=None, notify=False):
    global sid, n
    n += 1
    msg = {"jsonrpc": "2.0", "method": method}
    if not notify: msg["id"] = n
    if params is not None: msg["params"] = params
    h = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
         "MCP-Protocol-Version": "2025-06-18"}
    if sid: h["Mcp-Session-Id"] = sid
    r = urllib.request.urlopen(urllib.request.Request(url, json.dumps(msg).encode(), h))
    sid = r.headers.get("Mcp-Session-Id") or sid
    body = r.read().decode()
    if notify: return None
    for line in body.splitlines():
        if line.startswith("data:") and line[5:].strip():
            d = json.loads(line[5:])
            if d.get("id") == n: body = line[5:]; break
    d = json.loads(body)
    assert "error" not in d, d
    return d["result"]

def tool(name, args=None, ok=True):
    r = rpc("tools/call", {"name": name, "arguments": args or {}})
    text = r["content"][0]["text"]
    assert bool(r.get("isError")) != ok, f"{name}: {text}"
    return json.loads(text) if ok else text

init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                          "clientInfo": {"name": "e2e", "version": "0"}})
assert "marki_context" in init["instructions"]
rpc("notifications/initialized", notify=True)
names = {t["name"] for t in rpc("tools/list")["tools"]}
want = {"marki_context", "marki_search_cards", "marki_read_card", "marki_preview",
        "marki_write_card", "marki_add_media", "marki_find", "marki_read_model",
        "marki_write_model", "marki_status", "marki_push", "marki_flagged", "marki_query"}
assert want <= names, want - names
assert any(p["name"] == "make-cards" for p in rpc("prompts/list")["prompts"])

ctx = tool("marki_context")
assert ctx["cards"] == 0

# Path confinement.
assert "relative" in tool("marki_write_card", {"path": "../evil.md", "source": "x"}, ok=False)

# Preview a draft cloze without saving.
pv = tool("marki_preview", {"path": "geo/caps.md",
          "source": "Capital of France: **Paris**, of Italy: **Rome**.\n\n#cloze"})
assert len(pv["cards"]) == 2 and "[...]" in pv["cards"][0]["front"], pv

written = tool("marki_write_card", {"path": "geo/caps.md",
          "source": "Capital of France: **Paris**, of Italy: **Rome**.\n\n#cloze"})
cid = written.split("#id(")[1].split(")")[0]
tool("marki_write_card", {"path": "geo/q.md", "source": "Largest ocean?\n\n---\n\nPacific"})

# Overwrite needs the right expected_id.
assert "expected_id" in tool("marki_write_card", {"path": "geo/caps.md", "source": "x"}, ok=False)
tool("marki_write_card", {"path": "geo/caps.md", "expected_id": cid,
     "source": f"Capital of France: **Paris**, of Spain: **Madrid**.\n\n#id({cid}) #cloze"})

# A card that doesn't render is refused and not written.
assert "load model" in tool("marki_write_card", {"path": "bad.md", "source": "x\n\n#model(nope)"}, ok=False)

assert [c["path"] for c in tool("marki_search_cards", {"query": "madrid"})] == ["geo/caps.md"]
assert tool("marki_find", {"needle": cid}) == ["geo/caps.md"]
assert "Madrid" in tool("marki_read_card", {"path": "geo/caps.md"})

# Media.
media = tool("marki_add_media", {"dir": "icons", "name": "dot.svg",
        "base64": "PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnLz4="})
assert media == 'src = "icons/dot"', media

# Models: describe() is mandatory; a valid model renders.
lua = '''local M = {}
function M.card_names() return { "Ask" } end
function M.generate(note, ctx)
  return { AskFront = ctx:section_html(note, 1), AskBack = ctx:section_html(note, 2) }
end
%s
return M'''
assert "describe" in tool("marki_write_model", {"name": "qa", "lua": lua % ""}, ok=False)
tool("marki_write_model", {"name": "qa", "lua": lua % 'function M.describe() return "Q/A" end'})
assert tool("marki_read_model", {"name": "qa"})["lua"].startswith("local M")
assert tool("marki_read_model", {"name": "basic"})["builtin"]
assert "models are basic, cloze, qa" in tool("marki_read_model", {"name": "nope"}, ok=False)
# A card that makes no cards is refused.
assert "no cards" in tool("marki_write_card", {"path": "empty.md", "source": "\n---\n\nonly a back"}, ok=False)
doc = rpc("resources/read", {"uri": "marki://docs/models"})["contents"][0]["text"]
assert "section_html" in doc and "<Card>Front" in doc
tool("marki_write_card", {"path": "geo/m.md", "source": "Tallest mountain?\n\n---\n\nEverest\n\n#model(qa)"})
# Wrong generate keys: named error, not a silently missing card.
bad = lua.replace("AskFront", "Ask").replace("AskBack", "Back") % 'function M.describe() return "x" end'
err = tool("marki_write_model", {"name": "qa", "lua": bad}, ok=False)
assert "unknown key" in err and "AskFront" in err, err

st = tool("marki_status")
assert st["kind"] == "status" and not st["ok"], st
assert sorted(c["kind"] for c in st["changes"] if c["kind"] == "add") == ["add", "add", "add"], st
assert st["uncommitted"], st

# Simulate, then confirm; a wrong hash is refused.
sim = tool("marki_push")
assert sim["ok"] and sim["kind"] == "simulation" and "problems" not in sim, sim
assert [c["kind"] for c in sim["changes"]][:1] == ["model"], sim  # new note types listed first
col = sqlite3.connect(f"{w}/col.anki2")
assert col.execute("select count() from notes").fetchone()[0] == 0, "simulate wrote"
assert "plan changed" in tool("marki_push", {"confirm": True, "plan_hash": "nope"}, ok=False)
done = tool("marki_push", {"confirm": True, "plan_hash": sim["plan_hash"]})
assert done["ok"] and done["kind"] == "push", done
assert done["full_sync_required"], done  # new note types moved col.scm
assert {s["name"]: s["status"] for s in done["steps"]} == \
    {"media": "ok", "collection": "ok", "server": "skipped", "git": "ok"}, done
st = tool("marki_status")
assert st["ok"] and not st["changes"] and "uncommitted" not in st, st
assert col.execute("select count() from notes").fetchone()[0] == 3

# A tag-only edit is a change (the content hash covers fields only).
caps = open(f"{w}/p/geo/caps.md").read()
open(f"{w}/p/geo/caps.md", "w").write(caps.replace("#id(", "#retag #id("))
sim = tool("marki_push")
assert [(c["kind"], c["detail"]) for c in sim["changes"]] == [("update", "tags +retag")], sim
done = tool("marki_push", {"confirm": True, "plan_hash": sim["plan_hash"]})
assert done["ok"] and not done["full_sync_required"], done
tags = col.execute("select tags from notes where guid=?", (cid,)).fetchone()[0].split()
assert "retag" in tags, tags
assert not tool("marki_push")["changes"], "tag push is not idempotent"

# Config edits apply without a restart; a broken one fails tools loudly.
cfg = open(f"{w}/p/.marki/config.toml").read()
open(f"{w}/p/.marki/config.toml", "w").write(cfg + "\n[server]\nstop = [\"nonexistent-stop\"]\n")
assert "command not found: nonexistent-stop" in str(tool("marki_push")["problems"])
open(f"{w}/p/.marki/config.toml", "w").write(cfg + "\n[broken\n")
assert "no longer loads" in tool("marki_status", ok=False)
open(f"{w}/p/.marki/config.toml", "w").write(cfg)
assert tool("marki_status")["kind"] == "status"

# Flag a card as the user would in Anki, then find it.
col.execute("update cards set flags=1 where nid=(select id from notes where guid=?)", (cid,))
col.commit(); col.close()
fl = tool("marki_flagged", {"flag": 1})
assert fl and fl[0]["path"] == "geo/caps.md", fl

q = tool("marki_query", {"sql": "select guid, sfld from notes order by sfld"})
assert len(q["rows"]) == 3 and all(r["path"] for r in q["rows"]), q
assert "read-only" in tool("marki_query", {"sql": "delete from notes"}, ok=False)

res = rpc("resources/list")["resources"]
assert any(r["uri"] == "marki://card/geo/caps.md" for r in res)
assert "Madrid" in rpc("resources/read", {"uri": "marki://card/geo/caps.md"})["contents"][0]["text"]
print("mcp tools ok")
EOF

test -z "$(git status --porcelain)" || { echo "FAIL: push left the repo dirty"; git status; exit 1; }
git log --oneline | grep -q 'marki push' || { echo "FAIL: no push commit"; exit 1; }

py "$w/col.anki2" <<'EOF'
import sys
from anki.collection import Collection
col = Collection(sys.argv[1])
msg, ok = col.fix_integrity()
assert ok and msg.strip() == "Database rebuilt and optimized.", msg
assert col.card_count() == 4, col.card_count()  # cloze c1+c2, basic, qa
EOF
echo "all mcp e2e checks passed"
