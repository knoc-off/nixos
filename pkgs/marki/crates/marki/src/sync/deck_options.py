# Read or change deck options (presets and per-deck limits) in marki's local
# collection through Anki's own library: the same calls as Anki's Deck
# Options screen, so Anki validates and stores everything. Run by marki
# (sync/client.rs) with one JSON request as argv[1]; prints one JSON result
# line on stdout. Errors go to stderr with a non-zero exit.
#
# Request: {"collection", "action": "get" | "set", "deck"?,
#           "preset"?, "clone_from"?, "settings"?, "subdecks"?, "limits"?}
#
# Only an allowlisted set of preset fields is read or written. Nothing here
# changes the schema (no full sync), toggles FSRS or reschedules cards.
import json
import os
import re
import sys

# Anki prints debug output to stdout; see sync.py.
result_fd = os.dup(1)
os.dup2(2, 1)

from anki.collection import Collection
from anki.deck_config_pb2 import DeckConfig, UpdateDeckConfigsMode, UpdateDeckConfigsRequest

Config = DeckConfig.Config

INTS = [
    "new_per_day", "reviews_per_day", "graduating_interval_good", "graduating_interval_easy",
    "maximum_review_interval", "minimum_lapse_interval", "leech_threshold", "cap_answer_time_to_secs",
]
BOOLS = ["bury_new", "bury_reviews", "bury_interday_learning", "disable_autoplay", "show_timer"]
STEPS = ["learn_steps", "relearn_steps"]
ENUMS = [
    "new_card_insert_order", "new_card_gather_priority", "new_card_sort_order", "new_mix",
    "review_order", "interday_learning_mix", "leech_action",
]
FIELDS = INTS + ["desired_retention"] + BOOLS + STEPS + ENUMS
UNITS = {"s": 1 / 60, "m": 1, "h": 60, "d": 1440}


def fail(msg):
    sys.exit(msg)


def enum_values(field):
    """`{"due": 0, "random": 1}` for an enum field: the value names without
    the type's `NEW_CARD_INSERT_ORDER_` prefix, lowercased."""
    et = Config.DESCRIPTOR.fields_by_name[field].enum_type
    prefix = re.sub(r"(?<!^)(?=[A-Z])", "_", et.name).upper() + "_"
    return {v.name.removeprefix(prefix).lower(): v.number for v in et.values}


def fmt_steps(steps):
    out = []
    for m in steps:
        for unit, n in [("d", 1440), ("h", 60), ("m", 1)]:
            if m >= n and m % n == 0:
                out.append(f"{int(m // n)}{unit}")
                break
        else:
            out.append(f"{round(m * 60)}s")
    return " ".join(out)


def parse_steps(field, value):
    if not isinstance(value, str):
        fail(f"{field}: give steps as a string like \"1m 10m 1d\"")
    steps = []
    for part in value.split():
        m = re.fullmatch(r"(\d+(?:\.\d+)?)([smhd])", part)
        if not m:
            fail(f"{field}: bad step {part!r}; use a number with s, m, h or d, e.g. \"1m 10m 1d\"")
        steps.append(float(m[1]) * UNITS[m[2]])
    return steps


def read(c):
    out = {}
    for f in FIELDS:
        v = getattr(c, f)
        if f in STEPS:
            v = fmt_steps(v)
        elif f in ENUMS:
            v = {n: k for k, n in enum_values(f).items()}.get(v, v)
        elif f == "desired_retention":
            v = round(v, 3)
        out[f] = v
    return out


def apply(c, settings):
    unknown = sorted(set(settings) - set(FIELDS))
    if unknown:
        fail(f"unknown settings {', '.join(unknown)}; settable: {', '.join(FIELDS)}")
    for f, v in settings.items():
        if f in INTS:
            if not isinstance(v, int) or isinstance(v, bool) or v < 0:
                fail(f"{f}: needs a whole number >= 0, got {v!r}")
            if f == "maximum_review_interval" and v < 1:
                fail(f"{f}: needs at least 1 day")
            setattr(c, f, v)
        elif f in BOOLS:
            if not isinstance(v, bool):
                fail(f"{f}: needs true or false, got {v!r}")
            setattr(c, f, v)
        elif f == "desired_retention":
            if not isinstance(v, (int, float)) or not 0.7 <= v <= 0.99:
                fail(f"{f}: needs a number from 0.7 to 0.99, got {v!r}")
            c.desired_retention = v
        elif f in STEPS:
            steps = parse_steps(f, v)
            if f == "learn_steps" and not steps:
                fail("learn_steps: give at least one step")
            getattr(c, f)[:] = steps
        else:
            values = enum_values(f)
            if v not in values:
                fail(f"{f}: one of {', '.join(values)}, got {v!r}")
            setattr(c, f, values[v])


def normal_decks(col):
    """Every non-filtered deck: (name, id, preset id)."""
    return [(d["name"], d["id"], int(d["conf"])) for d in col.decks.all() if not d.get("dyn")]


def deck_id(col, name):
    for n, did, _ in normal_decks(col):
        if n.lower() == name.lower():
            return did
    if col.decks.id_for_name(name):
        fail(f"{name} is a filtered deck; those have no presets")
    fail(f"no deck {name!r}; decks: {', '.join(sorted(n for n, _, _ in normal_decks(col)))}")


def limits_of(cur):
    lim = cur.limits
    out = {}
    if lim.HasField("new"):
        out["new_per_day"] = lim.new
    if lim.HasField("review"):
        out["reviews_per_day"] = lim.review
    return out


def get(col, req):
    decks = normal_decks(col)
    did = deck_id(col, req["deck"]) if req.get("deck") else 1
    upd = col.decks.get_deck_configs_for_update(did)
    presets = [
        {
            "name": e.config.name,
            "decks": sorted(n for n, _, conf in decks if conf == e.config.id),
            "settings": read(e.config.config),
        }
        for e in upd.all_config
    ]
    out = {"fsrs": upd.fsrs, "presets": presets}
    if req.get("deck"):
        cur = upd.current_deck
        name = next((e.config.name for e in upd.all_config if e.config.id == cur.config_id), None)
        out["deck"] = {"name": cur.name, "preset": name, "limits": limits_of(cur)}
    return out


def set_(col, req):
    did = deck_id(col, req["deck"])
    upd = col.decks.get_deck_configs_for_update(did)
    by_name = {e.config.name.lower(): e.config for e in upd.all_config}
    preset = (req.get("preset") or "").strip()
    if not preset:
        cur = upd.current_deck.config_id
        preset = next(e.config.name for e in upd.all_config if e.config.id == cur)
    conf = DeckConfig()
    if preset.lower() in by_name:
        if req.get("clone_from"):
            fail(f"preset {preset!r} already exists; clone_from only applies to a new preset")
        conf.CopyFrom(by_name[preset.lower()])
        created = False
    else:
        src = req.get("clone_from")
        if src and src.lower() not in by_name:
            fail(f"no preset {src!r} to clone; presets: {', '.join(e.config.name for e in upd.all_config)}")
        conf.CopyFrom(by_name[src.lower()] if src else upd.defaults)
        conf.id = 0
        conf.name = preset
        created = True
    apply(conf.config, req.get("settings") or {})

    limits = upd.current_deck.limits
    for key, field in [("new_per_day", "new"), ("reviews_per_day", "review")]:
        if key in (req.get("limits") or {}):
            v = req["limits"][key]
            if v is None:
                limits.ClearField(field)
            elif isinstance(v, int) and not isinstance(v, bool) and v >= 0:
                setattr(limits, field, v)
            else:
                fail(f"limits.{key}: needs a whole number >= 0, or null to use the preset's")
    unknown = sorted(set(req.get("limits") or {}) - {"new_per_day", "reviews_per_day"})
    if unknown:
        fail(f"unknown limits {', '.join(unknown)}; settable: new_per_day, reviews_per_day")

    mode = UpdateDeckConfigsMode.UPDATE_DECK_CONFIGS_MODE_NORMAL
    if req.get("subdecks"):
        mode = UpdateDeckConfigsMode.UPDATE_DECK_CONFIGS_MODE_APPLY_TO_CHILDREN
    # The last config in `configs` is the one the deck gets; unlisted presets
    # are left alone. FSRS stays as it is and nothing is rescheduled.
    col.decks.update_deck_configs(
        UpdateDeckConfigsRequest(
            target_deck_id=did,
            configs=[conf],
            removed_config_ids=[],
            mode=mode,
            card_state_customizer=upd.card_state_customizer,
            limits=limits,
            new_cards_ignore_review_limit=upd.new_cards_ignore_review_limit,
            fsrs=upd.fsrs,
            apply_all_parent_limits=upd.apply_all_parent_limits,
            fsrs_reschedule=False,
            fsrs_health_check=upd.fsrs_health_check,
        )
    )
    after = get(col, {"deck": req["deck"]})
    return {
        "deck": after["deck"],
        "created_preset": created,
        "preset": next(p for p in after["presets"] if p["name"] == after["deck"]["preset"]),
    }


req = json.loads(sys.argv[1])
col = Collection(req["collection"])
try:
    if req["action"] == "get":
        out = get(col, req)
    elif req["action"] == "set":
        out = set_(col, req)
    else:
        fail(f"unknown action {req['action']!r}")
finally:
    col.close()

os.write(result_fd, (json.dumps(out) + "\n").encode())
