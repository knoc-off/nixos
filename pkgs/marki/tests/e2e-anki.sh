#!/usr/bin/env bash
# End-to-end check of marki push against Anki's own library as the oracle.
#
# Builds a fresh collection with Anki's pylib, pushes cards with the marki
# binary, fakes a review on every card, then exercises the risky writer
# paths (cloze card add/remove, basic->cloze model change, template rename,
# reorder, refused and permitted removal) and asserts after each step that:
#   - Anki's Check Database passes,
#   - review history (revlog) never ends up detached, except where removal
#     was explicitly allowed.
#
# Usage: tests/e2e-anki.sh [path/to/marki]   (defaults to target/debug/marki)
set -euo pipefail

here=$(cd "$(dirname "$0")/.." && pwd)
marki=${1:-$here/target/debug/marki}
anki_lib=$(nix build --no-link --print-out-paths 'nixpkgs#anki^lib')
python=$(nix build --no-link --print-out-paths 'nixpkgs#python313')/bin/python3
site=$(echo "$anki_lib"/lib/python3*/site-packages)
py() { PYTHONNOUSERSITE=true PYTHONPATH="$site" "$python" - "$@"; }

w=$(mktemp -d)
trap 'rm -rf "$w"' EXIT
mkdir "$w/p"
cd "$w/p"

py "$w/col.anki2" <<'EOF'
import sys
from anki.collection import Collection
Collection(sys.argv[1]).close()
EOF

"$marki" init >/dev/null 2>&1
echo "collection = \"$w/col.anki2\"" >>.marki/config.toml

# Prints "<notetype> <template> ord=<n> revlog=<n>" per card, then the number
# of revlog rows whose card no longer exists. Fails if Check Database has
# anything to fix.
state() {
  py "$w/col.anki2" <<'EOF'
import sys
from anki.collection import Collection
col = Collection(sys.argv[1])
msg, ok = col.fix_integrity()
# A clean collection reports only "rebuilt and optimized"; anything else is
# Check Database repairing something marki wrote.
assert ok and msg.strip() == "Database rebuilt and optimized.", msg
for cid in col.find_cards("tag:marki"):
    c = col.get_card(cid); t = c.note().note_type()
    name = t["tmpls"][c.ord]["name"] if t["type"] == 0 else "Cloze"
    n = col.db.scalar("select count() from revlog where cid=?", cid)
    print(f"{t['name']} {name} ord={c.ord} revlog={n}")
print("detached", col.db.scalar("select count() from revlog where cid not in (select id from cards)"))
col.close()
EOF
}

expect() {
  local got
  got=$(state | sort)
  if [[ "$got" != "$(printf '%s\n' "$@" | sort)" ]]; then
    echo "FAIL at: $step"
    echo "--- expected"; printf '%s\n' "$@" | sort
    echo "--- got"; echo "$got"
    exit 1
  fi
  # marki's own structural check must agree with Anki's Check Database.
  if ! "$marki" check >"$w/check.log" 2>&1; then
    echo "FAIL at: $step (marki check)"; cat "$w/check.log"; exit 1
  fi
  echo "ok: $step"
}

review_all() {
  py "$w/col.anki2" <<'EOF'
import sys
from anki.collection import Collection
col = Collection(sys.argv[1])
for i, cid in enumerate(col.find_cards("tag:marki")):
    if not col.db.scalar("select count() from revlog where cid=?", cid):
        col.db.execute("insert into revlog (id,cid,usn,ease,ivl,lastIvl,factor,time,type) values (?,?,-1,3,5,0,2500,1000,1)", 1790000000000 + cid % 100000 + i, cid)
        col.db.execute("update cards set type=2, queue=2, ivl=5, due=100, reps=1 where id=?", cid)
# Let Anki fill in derived fields (last review time) for the fake reviews,
# so the Check Database assertions below only see marki's own writes.
col.fix_integrity()
col.close()
EOF
}

push() { "$marki" push 2>&1 | grep -E '^Error|errors\)' | grep -v ' 0 errors)' || true; }

cat >.marki/models/duo.lua <<'EOF'
local M = {}
function M.card_names() return { "Ask", "Reverse" } end
function M.generate(note, ctx)
  local h = note:heading(1):text()
  return { AskFront = h, AskBack = "a", ReverseFront = "a", ReverseBack = h }
end
return M
EOF
printf 'The capital of France is **Paris**.\n' >switch.md
printf 'Planets: **Jupiter**, **Saturn**, **Uranus**.\n\n#cloze\n' >planets.md
printf '# Berlin\n\n#model(duo)\n' >duo.md
"$marki" fmt >/dev/null 2>&1

step="simulate writes nothing"
"$marki" push --simulate >"$w/sim.log" 2>&1 || { cat "$w/sim.log"; echo "FAIL: $step"; exit 1; }
grep -q 'simulation clean' "$w/sim.log" || { cat "$w/sim.log"; echo "FAIL: $step"; exit 1; }
[[ -z "$(state | grep -v '^detached')" ]] || { echo "FAIL: $step"; exit 1; }
echo "ok: $step"

step="initial push"
push
# Written like an Anki client: everything marki added waits for upload.
py "$w/col.anki2" <<'EOF' || { echo "FAIL: $step (pending usn)"; exit 1; }
import sys
from anki.collection import Collection
col = Collection(sys.argv[1])
for t in ["notes", "cards"]:
    assert col.db.scalar(f"select count() from {t} where usn != -1") == 0, t
assert col.db.scalar("select count() from notetypes where name like 'marki:%' and usn != -1") == 0
assert col.db.scalar("select usn from col") == 0, "col.usn is the server's, not ours"
col.close()
EOF
review_all
expect "marki:basic Card ord=0 revlog=1" \
  "marki:cloze Cloze ord=0 revlog=1" "marki:cloze Cloze ord=1 revlog=1" "marki:cloze Cloze ord=2 revlog=1" \
  "marki:duo Ask ord=0 revlog=1" "marki:duo Reverse ord=1 revlog=1" "detached 0"

step="remove cloze c3"
sed -i 's/, \*\*Uranus\*\*//' planets.md
grep -q Uranus planets.md && { echo "FAIL: sed did not edit planets.md"; exit 1; }
push
expect "marki:basic Card ord=0 revlog=1" \
  "marki:cloze Cloze ord=0 revlog=1" "marki:cloze Cloze ord=1 revlog=1" \
  "marki:duo Ask ord=0 revlog=1" "marki:duo Reverse ord=1 revlog=1" "detached 1"

step="basic -> cloze keeps history"
sed -i 's/^\(#id([0-9a-f]*)\)$/\1 #cloze/' switch.md
push
expect "marki:cloze Cloze ord=0 revlog=1" \
  "marki:cloze Cloze ord=0 revlog=1" "marki:cloze Cloze ord=1 revlog=1" \
  "marki:duo Ask ord=0 revlog=1" "marki:duo Reverse ord=1 revlog=1" "detached 1"

step="rename Ask -> Question keeps history"
sed -i 's/"Ask", "Reverse"/"Question", "Reverse"/; s/AskFront/QuestionFront/; s/AskBack/QuestionBack/; s/^local M = {}/local M = { renames = { Ask = "Question" } }/' .marki/models/duo.lua
push
expect "marki:cloze Cloze ord=0 revlog=1" \
  "marki:cloze Cloze ord=0 revlog=1" "marki:cloze Cloze ord=1 revlog=1" \
  "marki:duo Question ord=0 revlog=1" "marki:duo Reverse ord=1 revlog=1" "detached 1"

step="reorder keeps history"
sed -i 's/{ "Question", "Reverse" }/{ "Reverse", "Question" }/; s/renames = { Ask = "Question" }//' .marki/models/duo.lua
push
expect "marki:cloze Cloze ord=0 revlog=1" \
  "marki:cloze Cloze ord=0 revlog=1" "marki:cloze Cloze ord=1 revlog=1" \
  "marki:duo Question ord=1 revlog=1" "marki:duo Reverse ord=0 revlog=1" "detached 1"

step="removal refused without permission, other notes still pushed"
sed -i 's/{ "Reverse", "Question" }/{ "Question" }/; s/, ReverseFront = "a", ReverseBack = h//' .marki/models/duo.lua
sed -i 's/Jupiter/Mars/' planets.md
out=$("$marki" push 2>&1 || true)
grep -q 'would be removed' <<<"$out" || { echo "FAIL: $step (no refusal)"; echo "$out"; exit 1; }
expect "marki:cloze Cloze ord=0 revlog=1" \
  "marki:cloze Cloze ord=0 revlog=1" "marki:cloze Cloze ord=1 revlog=1" \
  "marki:duo Question ord=1 revlog=1" "marki:duo Reverse ord=0 revlog=1" "detached 1"

step="removal with allow_card_removal"
sed -i 's/^local M = {.*/local M = { allow_card_removal = true }/' .marki/models/duo.lua
push
expect "marki:cloze Cloze ord=0 revlog=1" \
  "marki:cloze Cloze ord=0 revlog=1" "marki:cloze Cloze ord=1 revlog=1" \
  "marki:duo Question ord=0 revlog=1" "detached 2"

echo "all e2e checks passed"
