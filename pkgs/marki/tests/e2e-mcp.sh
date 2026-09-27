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
py "$port" "$w" "$here" <<'EOF'
import sys, json, urllib.request, sqlite3, base64
port, w, here = sys.argv[1], sys.argv[2], sys.argv[3]
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
    return json.loads(text) if ok and name != "marki_docs" else text

init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                          "clientInfo": {"name": "e2e", "version": "0"}})
assert "marki_context" in init["instructions"]
rpc("notifications/initialized", notify=True)
names = {t["name"] for t in rpc("tools/list")["tools"]}
want = {"marki_context", "marki_search_cards", "marki_read_card", "marki_preview",
        "marki_write_card", "marki_add_media", "marki_read_model",
        "marki_write_model", "marki_status", "marki_push", "marki_query",
        "marki_delete_card", "marki_move_card", "marki_docs", "marki_write_cards",
        "marki_map_units", "marki_map_find", "marki_map_define", "marki_map_list", "marki_media_list",
        "marki_map_render", "marki_map_get"}
assert want <= names, want - names
assert not names & {"marki_find", "marki_flagged"}, names
assert "marki_docs" in init["instructions"]
assert "layers" in tool("marki_docs", {"topic": "map"}) and "### Cloze" in tool("marki_docs", {"topic": "cards"})
assert "topics: cards" in tool("marki_docs", {"topic": "nope"}, ok=False)
assert "section_html" in rpc("resources/read", {"uri": "marki://docs/models"})["contents"][0]["text"]

# Module lookup tools.
units = tool("marki_map_units", {"iso": "deu", "level": 1})
assert units["ref_prefix"] == "adm1/DEU/" and "bayern" in units["units"], units
assert "unknown country" in tool("marki_map_units", {"iso": "XXX", "level": 1}, ok=False)
assert tool("marki_media_list")["src"] == []

# A wrong region name lists the valid ones, and the error points at the docs and tools.
bad_map = "Which state?\n\n```map\n[layers.base]\nfeatures = [\"country/DEU\"]\n[layers.answer]\nhighlights = [\"adm1/DEU/Bavaria\"]\n```\n\n---\n\nBavaria"
err = tool("marki_write_card", {"path": "geo/by.md", "source": bad_map}, ok=False)
assert "bayern" in err and 'marki_docs("map")' in err and "marki_map_units" in err, err
assert "marki_map_find" in tool("marki_preview", {"path": "geo/by.md", "source": bad_map})["docs"]
assert any(p["name"] == "make-cards" for p in rpc("prompts/list")["prompts"])

ctx = tool("marki_context")
assert ctx["cards"] == 0
mapb = [b for b in ctx["blocks"] if b["fence"] == "```map"]
assert mapb and mapb[0]["tools"] == ["marki_map_units", "marki_map_find", "marki_map_define", "marki_map_list", "marki_map_get"], ctx["blocks"]
assert {d["topic"] for d in ctx["docs"]} == {"cards", "map", "media", "models"}, ctx["docs"]

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
assert [c["path"] for c in tool("marki_search_cards", {"query": cid})] == ["geo/caps.md"]
assert "Madrid" in tool("marki_read_card", {"path": "geo/caps.md"})

# Media.
media = tool("marki_add_media", {"dir": "icons", "name": "dot.svg",
        "base64": "PHN2ZyB4bWxucz0naHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmcnLz4="})
assert media == 'src = "icons/dot"', media
assert tool("marki_media_list", {"filter": "dot"})["src"] == ["icons/dot"]

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
# Compact by default: counts per kind and deck dir; detail gives every line, same plan.
full = tool("marki_push", {"detail": True})
assert sim["summary"] == {"add": 3, "model": 3} and full["plan_hash"] == sim["plan_hash"], sim["summary"]
assert sum(d.get("add", 0) for d in sim["by_dir"].values()) == 3, sim["by_dir"]
assert "model" not in str(sim["by_dir"]) and "changes_omitted" not in full
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

# Delete: file first (guarded by id), then the push suspends or deletes.
qid = open(f"{w}/p/geo/q.md").read().split("#id(")[1].split(")")[0]
assert "not nope" in tool("marki_delete_card", {"path": "geo/q.md", "expected_id": "nope"}, ok=False)
tool("marki_delete_card", {"path": "geo/q.md", "expected_id": qid})
soft = tool("marki_push")
assert [c["detail"].split()[0] for c in soft["changes"] if c["kind"] == "orphan"] == ["suspend"], soft
hard = tool("marki_push", {"delete_orphans": True})
assert [c["detail"].split()[0] for c in hard["changes"] if c["kind"] == "orphan"] == ["delete"], hard
assert soft["plan_hash"] != hard["plan_hash"]
assert "plan changed" in tool("marki_push", {"confirm": True, "plan_hash": soft["plan_hash"], "delete_orphans": True}, ok=False)
done = tool("marki_push", {"confirm": True, "plan_hash": hard["plan_hash"], "delete_orphans": True})
assert done["ok"], done
assert col.execute("select count() from notes where guid=?", (qid,)).fetchone()[0] == 0

# Config edits apply without a restart; a broken one fails tools loudly.
cfg = open(f"{w}/p/.marki/config.toml").read()
open(f"{w}/p/.marki/config.toml", "w").write(cfg + "\n[server]\nstop = [\"nonexistent-stop\"]\n")
assert "command not found: nonexistent-stop" in str(tool("marki_push")["problems"])
open(f"{w}/p/.marki/config.toml", "w").write(cfg + "\n[broken\n")
assert "no longer loads" in tool("marki_status", ok=False)
open(f"{w}/p/.marki/config.toml", "w").write(cfg)
assert tool("marki_status")["kind"] == "status"

# Move: the file changes directory, the push moves the same note.
mid = open(f"{w}/p/geo/m.md").read().split("#id(")[1].split(")")[0]
nid = col.execute("select id from notes where guid=?", (mid,)).fetchone()[0]
assert "already exists" in tool("marki_move_card", {"path": "geo/m.md", "new_path": "geo/caps.md", "expected_id": mid}, ok=False)
mv = tool("marki_move_card", {"path": "geo/m.md", "new_path": "nature/peaks/m.md", "expected_id": mid})
assert mv["moved"] == "nature/peaks/m.md" and not mv["render_errors"], mv
sim = tool("marki_push")
assert [(c["kind"], c["detail"]) for c in sim["changes"]] == [("move", "deck geo -> nature::peaks")], sim
assert tool("marki_push", {"confirm": True, "plan_hash": sim["plan_hash"]})["ok"]
assert col.execute("select id from notes where guid=?", (mid,)).fetchone()[0] == nid

# A flag set in Anki is cleared by the push that changes the note.
col.execute("update cards set flags=1 where nid=(select id from notes where guid=?)", (cid,))
col.commit()
fl = tool("marki_query", {"sql": "select distinct n.guid from cards c join notes n on n.id=c.nid where c.flags & 7 = 1"})
assert [r["path"] for r in fl["rows"]] == ["geo/caps.md"], fl
caps = open(f"{w}/p/geo/caps.md").read()
open(f"{w}/p/geo/caps.md", "w").write(caps.replace("Madrid", "Madrid (Spain)"))
sim = tool("marki_push")
assert [(c["kind"], c["detail"]) for c in sim["changes"]] == [("update", "unflag")], sim
assert tool("marki_push", {"confirm": True, "plan_hash": sim["plan_hash"]})["ok"]
assert col.execute("select count() from cards where flags & 7 != 0").fetchone()[0] == 0
col.close()

q = tool("marki_query", {"sql": "select guid, sfld from notes order by sfld"})
assert len(q["rows"]) == 2 and all(r["path"] for r in q["rows"]), q
assert "read-only" in tool("marki_query", {"sql": "delete from notes"}, ok=False)

res = rpc("resources/list")["resources"]
assert any(r["uri"] == "marki://card/geo/caps.md" for r in res)
assert "Madrid" in rpc("resources/read", {"uri": "marki://card/geo/caps.md"})["contents"][0]["text"]

# Batch write: one broken card means nothing is written.
import os
geo_lua = open(f"{here}/models/geographic-location.lua").read()
tool("marki_write_model", {"name": "geographic-location", "lua": geo_lua})
country = lambda name, iso: (f"# {name}\n\n```map\n[layers.base]\nfeatures = [\"country/{iso}\"]\n"
                             f"context = [\"neighbors/{iso}\"]\n[layers.answer]\nhighlights = [\"country/{iso}\"]\n```\n\n"
                             f"#model(geographic-location)")
batch = [{"path": "batch/fr.md", "source": country("France", "FRA")},
         {"path": "batch/xx.md", "source": country("Nowhere", "XXX")}]
err = tool("marki_write_cards", {"cards": batch}, ok=False)
assert "1 of 2" in err and "batch/xx.md" in err and "batch/fr.md" not in err, err
assert not os.path.exists(f"{w}/p/batch"), "partial batch written"
batch[1] = {"path": "batch/es.md", "source": country("Spain", "ESP")}
assert "twice" in tool("marki_write_cards", {"cards": batch + batch[:1]}, ok=False)
out = tool("marki_write_cards", {"cards": batch})
assert [c["path"] for c in out["written"]] == ["batch/fr.md", "batch/es.md"], out
cards = tool("marki_preview", {"path": "batch/fr.md"})["cards"]
assert [c["name"] for c in cards] == ["Locate", "Identify"], cards
# Cleaned up again so the final repo/collection checks stay as they were.
import shutil; shutil.rmtree(f"{w}/p/batch")
os.remove(f"{w}/p/.marki/models/geographic-location.lua")

# Custom geometry: define from GeoJSON, then a card uses geo/<name>.
wall = {"type": "FeatureCollection", "features": [
    {"type": "Feature", "geometry": {"type": "LineString", "coordinates": [[100, 38], [106, 40], [112, 40.5]]}},
    {"type": "Feature", "geometry": {"type": "LineString", "coordinates": [[112, 40.5], [117, 40.4], [119.8, 40]]}}]}
d = tool("marki_map_define", {"name": "great-wall", "from": {"geojson": wall}})
assert d["ref"] == "geo/great-wall" and d["kind"] == "line" and d["points"] == 6, d
assert d["bbox"] == [100, 38, 119.8, 40.5], d
assert "exactly one" in tool("marki_map_define", {"name": "x", "from": {"osm": [], "geojson": wall}}, ok=False)
assert "bad geo name" in tool("marki_map_define", {"name": "../x", "from": {"geojson": wall}}, ok=False)
assert tool("marki_map_list")["features"] == ["geo/great-wall"]
g = tool("marki_map_get", {"name": "geo/great-wall", "geometry": True})
assert g["bbox"] == d["bbox"] and g["points"] == 6 and g["geometry"]["type"] == "MultiLineString", g
assert "geometry" not in tool("marki_map_get", {"name": "great-wall"})
# marki_map_get isn't geo/-only: any ref works, and reports a centre too.
c = tool("marki_map_get", {"name": "country/DEU"})
assert c["kind"] == "area" and len(c["center"]) == 2, c
assert tool("marki_context")["custom_geometry"] == ["geo/great-wall"]
wall_card = ("Where is the Great Wall?\n\n```map\n[layers.base]\nfeatures = [\"country/CHN\"]\n"
             "[layers.answer]\nhighlights = [\"geo/great-wall\"]\n```\n\n---\n\nNorthern China")
pv = tool("marki_preview", {"path": "wall.md", "source": wall_card})
assert not pv["errors"] and pv["assets"], pv
# The card's map comes back as a PNG (Basic: the map is on the front only;
# marki_map_render below shows both sides).
r = rpc("tools/call", {"name": "marki_preview", "arguments": {"path": "wall.md", "source": wall_card}})
imgs = [c for c in r["content"] if c["type"] == "image"]
assert pv["images"] == ["Card front #1"] and len(imgs) == 1, (pv["images"], pv["image_errors"])
assert base64.b64decode(imgs[0]["data"]).startswith(b"\x89PNG")
r = rpc("tools/call", {"name": "marki_preview", "arguments": {"path": "wall.md", "source": wall_card, "images": False}})
assert not [c for c in r["content"] if c["type"] == "image"]
# Media changes are counted, not listed, unless detail=true.
tool("marki_write_card", {"path": "wall.md", "source": wall_card})
sim = tool("marki_push")
full = tool("marki_push", {"detail": True})
media = [c for c in full["changes"] if c["kind"] == "media"]
assert media and sim["summary"]["media"] == len(media), (sim["summary"], full["changes"])
assert not [c for c in sim["changes"] if c["kind"] == "media"] and sim["changes_omitted"] == len(media), sim
assert sim["by_dir"] == {"": {"add": 1}}, sim["by_dir"]
os.remove(f"{w}/p/wall.md")
# A block alone, with a fixed frame and a dashed answer.
blk = ("[viewport]\nbbox = [110, 38, 120, 42]\n[layers.base]\nfeatures = [\"country/CHN\"]\n"
       "[layers.answer]\nhighlights = [\"geo/great-wall\"]\n[layers.answer.style]\ndash = \"6 4\"\n")
r = rpc("tools/call", {"name": "marki_map_render", "arguments": {"source": blk}})
assert not r.get("isError") and [c["text"] for c in r["content"] if c["type"] == "text"][1:] == ["front", "back"], r["content"][0]
front, back = [base64.b64decode(c["data"]) for c in r["content"] if c["type"] == "image"]
assert front != back, "the back shows the answer layer"
assert "parse" in tool("marki_map_render", {"source": "[viewport]\nbbox = 1\n"}, ok=False)
# center + span_km frames on a point ref; aspect widens the short axis.
c = tool("marki_map_get", {"name": "geo/great-wall"})
mid_lon = (c["bbox"][0] + c["bbox"][2]) / 2
mid_lat = (c["bbox"][1] + c["bbox"][3]) / 2
tool("marki_map_define", {"name": "wall-mid", "from": {"geojson": {"type": "Point", "coordinates": [mid_lon, mid_lat]}}})
zoom = ("size = [400, 400]\n[viewport]\ncenter = \"geo/wall-mid\"\nspan_km = 50\naspect = 2.0\n"
        "[layers.base]\nfeatures = [\"geo/great-wall\"]\n")
zr = rpc("tools/call", {"name": "marki_map_render", "arguments": {"source": zoom}})
assert not zr.get("isError"), zr
assert "only one" in tool("marki_map_render", {"source": "[viewport]\nbbox = [1,2,3,4]\ncenter = \"geo/wall-mid\"\nspan_km = 1\n[layers.base]\nfeatures = [\"geo/wall-mid\"]\n"}, ok=False)
err = tool("marki_preview", {"path": "wall.md", "source": wall_card.replace("great-wall", "nope")})["errors"]
assert "marki_map_define" in str(err), err
shutil.rmtree(f"{w}/p/.marki/geo")
print("mcp tools ok")
EOF

test -z "$(git status --porcelain)" || { echo "FAIL: push left the repo dirty"; git status; exit 1; }
git log --oneline | grep 'marki push' >/dev/null || { echo "FAIL: no push commit"; exit 1; }

py "$w/col.anki2" <<'EOF'
import sys
from anki.collection import Collection
col = Collection(sys.argv[1])
msg, ok = col.fix_integrity()
assert ok and msg.strip() == "Database rebuilt and optimized.", msg
assert col.card_count() == 3, col.card_count()  # cloze c1+c2, qa (basic deleted)
EOF
echo "all mcp e2e checks passed"
