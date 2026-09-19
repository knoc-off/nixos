"""Align Home Assistant entity_ids with the NixOS device registry.

HA anchors an entity_id at first discovery and never revisits it, so a
zigbee2mqtt rename leaves the old id in place: the living room light stays
`light.light_1` long after its friendly_name became `livingroom_light`.

This renames those rows through the running instance's websocket API. It must
go through the API rather than editing .storage directly, because recorder
migrates a rename's history only when it observes
EVENT_ENTITY_REGISTRY_UPDATED (components/recorder/entity_registry.py). An
offline edit fires no event and would strand every entity's history under its
old id.

Scope is every entity zigbee2mqtt owns for a device declared in devices.nix,
primary and secondary alike, so `sensor.plug_1_power` follows the device name
as well. Anything else in the registry is untouched.

Idempotent: entities already at the target id are skipped, so the steady state
is a no-op and this can run on every boot.
"""

import asyncio
import json
import os
import sys

import websockets

# zigbee2mqtt mints every entity's unique_id as `<ieee>_<suffix>_zigbee2mqtt`.
Z2M_SUFFIX = "_zigbee2mqtt"

# Our own sun-follow entities are `sun_follow_<ieee>_<suffix>` (see
# mqtt-automations/default.nix, where they were re-keyed onto the IEEE
# address for exactly this reason).
SUN_FOLLOW_PREFIX = "sun_follow_"


def target_for(entity, wanted):
    """Desired entity_id for `entity`, or None to leave it alone.

    Both naming schemes carry the device's IEEE address in the unique_id,
    which is the one identifier that survives a rename. Anything whose IEEE
    isn't in the device registry -- the z2m bridge's own entities, the
    device-less daylight sensor, anything paired but not declared -- returns
    None and is never touched.
    """
    uid = entity.get("unique_id")
    if not isinstance(uid, str):
        return None
    domain = entity["entity_id"].split(".")[0]

    if uid.endswith(Z2M_SUFFIX):
        ieee, _, suffix = uid[: -len(Z2M_SUFFIX)].partition("_")
        if (name := wanted.get(ieee)) is None:
            return None
        # A suffix equal to the domain marks the device's primary entity
        # (`light.livingroom_light`); anything else is a secondary one
        # (`sensor.livingroom_plug_1_power`).
        return f"{domain}.{name}" if suffix == domain else f"{domain}.{name}_{suffix}"

    if uid.startswith(SUN_FOLLOW_PREFIX):
        ieee, _, suffix = uid[len(SUN_FOLLOW_PREFIX):].partition("_")
        if (name := wanted.get(ieee)) is None:
            return None
        # Suffixes are kebab-case in the unique_id (`follow-sunrise`).
        return f"{domain}.{name}_sun_follow_{suffix.replace('-', '_')}"

    return None


def plan_renames(registry, wanted):
    """Work out which entities need renaming.

    `registry` is the entity list from config/entity_registry/list, `wanted`
    maps IEEE address -> desired device name (generated from devices.nix).

    Returns (todo, blocked).
    """
    taken = {e["entity_id"] for e in registry}

    todo, blocked = [], []
    for e in registry:
        target = target_for(e, wanted)
        if target is None or target == e["entity_id"]:
            continue
        # Renaming onto an id that is already in use makes recorder drop the
        # history migration ("because the new entity_id is already in use"),
        # so report it and leave the entity alone.
        entry = {"from": e["entity_id"], "to": target}
        (blocked if target in taken else todo).append(entry)

    return todo, blocked


async def run(url, token, wanted):
    async with websockets.connect(url, max_size=None) as ws:
        # Handshake: server sends auth_required, we reply, server confirms.
        await ws.recv()
        await ws.send(json.dumps({"type": "auth", "access_token": token}))
        auth = json.loads(await ws.recv())
        if auth.get("type") != "auth_ok":
            sys.exit(f"authentication failed: {auth.get('message', auth)}")

        await ws.send(json.dumps({"id": 1, "type": "config/entity_registry/list"}))
        while True:
            msg = json.loads(await ws.recv())
            if msg.get("id") == 1 and msg.get("type") == "result":
                break
        if not msg.get("success"):
            sys.exit(f"could not list entity registry: {msg.get('error')}")

        todo, blocked = plan_renames(msg["result"], wanted)

        for b in blocked:
            print(
                f"skipping {b['from']} -> {b['to']}: target already in use",
                file=sys.stderr,
            )

        if not todo:
            print("all entity_ids already match the device registry")
            return

        renamed = 0
        for n, r in enumerate(todo, start=2):
            await ws.send(
                json.dumps(
                    {
                        "id": n,
                        "type": "config/entity_registry/update",
                        "entity_id": r["from"],
                        "new_entity_id": r["to"],
                    }
                )
            )
            while True:
                res = json.loads(await ws.recv())
                if res.get("id") == n:
                    break
            if res.get("success"):
                print(f"renamed {r['from']} -> {r['to']}")
                renamed += 1
            else:
                err = (res.get("error") or {}).get("message", "unknown")
                print(f"rename failed {r['from']} -> {r['to']}: {err}", file=sys.stderr)

        print(f"renamed {renamed} of {len(todo)} entities")


def selftest():
    """Check the naming rules. Run with --selftest."""
    W = {"0xAAA": "livingroom_light", "0xBBB": "livingroom_plug_1"}
    e = lambda eid, uid: {"entity_id": eid, "unique_id": uid}  # noqa: E731

    # Primary vs secondary z2m entities.
    assert target_for(e("light.light_1", "0xAAA_light_zigbee2mqtt"), W) == (
        "light.livingroom_light"
    )
    assert target_for(e("sensor.plug_1_power", "0xBBB_power_zigbee2mqtt"), W) == (
        "sensor.livingroom_plug_1_power"
    )
    # Sun-follow, including kebab -> snake in the suffix.
    assert target_for(e("switch.x", "sun_follow_0xAAA_follow-sunrise"), W) == (
        "switch.livingroom_light_sun_follow_follow_sunrise"
    )
    # Unknown device, foreign integration and device-less entities: untouched.
    assert target_for(e("light.x", "0xZZZ_light_zigbee2mqtt"), W) is None
    assert target_for(e("sensor.x", "something_else"), W) is None
    assert target_for(e("sensor.daylight", "sun_follow_daylight_pct"), W) is None
    assert target_for(e("sensor.x", None), W) is None

    # A taken target is skipped rather than renamed over.
    reg = [
        e("light.light_1", "0xAAA_light_zigbee2mqtt"),
        e("light.livingroom_light", "0xCCC_light_zigbee2mqtt"),
    ]
    todo, blocked = plan_renames(reg, W)
    assert (todo, len(blocked)) == ([], 1), (todo, blocked)

    # Renaming is idempotent: applying the plan leaves nothing to do.
    reg = [e("light.light_1", "0xAAA_light_zigbee2mqtt")]
    todo, blocked = plan_renames(reg, W)
    assert len(todo) == 1 and not blocked
    assert plan_renames([e(todo[0]["to"], reg[0]["unique_id"])], W) == ([], [])

    print("selftest ok")


def main():
    if "--selftest" in sys.argv:
        selftest()
        return
    with open(os.environ["TOKEN_FILE"]) as f:
        token = f.read().strip()
    with open(os.environ["RENAMES_FILE"]) as f:
        wanted = json.load(f)
    asyncio.run(run(os.environ["HA_URL"], token, wanted))


if __name__ == "__main__":
    main()
