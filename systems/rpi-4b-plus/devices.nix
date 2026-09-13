# Single source of truth for every Zigbee device: which room it's in, what
# kind of thing it is, its IEEE address, and (optionally) its sun-follow
# config. Everything else -- zigbee2mqtt's friendly name, HA's suggested
# area, the sun-follow topics/env, the dashboard -- is derived from this one
# table. Rename or move a device by editing its entry here; every consumer
# (z2m topics, sun-follow services, dashboard cards) follows in one rebuild.
#
# Room is structural, not an annotation: a device only exists inside
# `rawDevices.<room>.<device>`, so it is physically impossible for a device's
# key and its room to disagree (unlike a flat list with a separate `room =`
# field, which can silently point at the wrong room). Nix's own duplicate-key
# check means two devices can never collide on `<room>.<key>` either --
# defining the same attribute twice is a hard eval error, not silent
# overwrite, so no separate uniqueness check is needed.
#
# `kind` drives dashboard presentation defaults (icon, card type) -- see
# services/home-assistant/dashboard.nix. It carries no z2m/HA semantics of
# its own. It's a plain string-valued attrset (not an enum type) purely so a
# typo like `kinds.ligth` fails at eval time instead of silently producing a
# `kind` that matches no case downstream.
#
# Renaming/moving a device does NOT rename its already-registered HA
# entity_id (e.g. `light.light_1` stays `light.light_1` even after z2m's
# friendly_name becomes `livingroom_light`) -- entity_id is anchored once at
# first discovery. The dashboard's entity-id table therefore records the
# current, pre-rename entity_ids explicitly; see the comment there.
let
  kinds = {
    light = "light";
    plug = "plug";
    button = "button";
    motion = "motion";
    sensor = "sensor";
  };

  # Display label plus the friendly-name prefix each device in the room gets
  # (hyphen-free -- z2m friendly names double as MQTT topic segments).
  roomMeta = {
    living-room = {
      label = "Living Room";
      slug = "livingroom";
    };
    kitchen = {
      label = "Kitchen";
      slug = "kitchen";
    };
    bedroom = {
      label = "Bedroom";
      slug = "bedroom";
    };
  };

  # `id`: zigbee IEEE address (the permanent, hardware-anchored identifier).
  rawDevices = {
    living-room = {
      light = {
        id = "0x001788010ffdd431";
        kind = kinds.light;
      };
      plug_1 = {
        id = "0xa4c1385aef501143";
        kind = kinds.plug;
      };
      plug_2 = {
        id = "0xa4c13861447acbe2";
        kind = kinds.plug;
      };
      plug_3 = {
        id = "0xa4c1388762b9e41c";
        kind = kinds.plug;
      };
      button = {
        id = "0xa4c1381618f0f10c";
        kind = kinds.button;
      };
    };

    kitchen = {
      light = {
        id = "0x001788010f2c225a";
        kind = kinds.light;
      };
      plug = {
        id = "0xa4c1388806d132cb";
        kind = kinds.plug;
      };
      motion = {
        id = "0xa4c138ce243fe709";
        kind = kinds.motion;
      };
      temp_probe = {
        # SONOFF SNZB-02LD, waterproof probe.
        id = "0xa4c1380900f2ffff";
        kind = kinds.sensor;
      };
    };

    bedroom = {
      light = {
        id = "0x001788010f2c1a11";
        kind = kinds.light;
      };
      button = {
        id = "0xa4c138aa5aaccfa5";
        kind = kinds.button;
      };
      dial = {
        # Tuya TS004F, 4-button scene dial.
        id = "0xa4c13880fa2af7d7";
        kind = kinds.button;
      };
    };
  };
in
rec {
  inherit kinds;
  rooms = builtins.mapAttrs (roomKey: meta: meta // { name = roomKey; }) roomMeta;

  # Zigbee groups. `id` is the Zigbee group ID (1-65534, must be stable --
  # changing it orphans the group on every member device's radio).
  #
  # Only `friendly_name` reaches configuration.yaml: z2m removed
  # `groups.<id>.devices` in settings version 2 and silently drops it, so
  # membership is applied at runtime by the z2m-groups oneshot (see
  # services/z2m-groups.nix) via the bridge request API.
  #
  # A `bind = { from = <device>; clusters = [...]; }` here additionally binds a
  # button's endpoint straight to the group at the Zigbee level, so it keeps
  # controlling the group with this host powered off. Left off for now -- the
  # button is battery-powered and must be awake to accept the bind, so it
  # needs a manual press at the moment z2m-groups runs. Re-add when wanted.
  zigbeeGroups = {
    living_room = {
      id = 1;
      members = with devices.living-room; [
        light
        plug_1
        plug_2
        plug_3
      ];
    };
  };

  # `rawDevices` with each entry's zigbee2mqtt friendly name (`<slug>_<key>`)
  # and resolved room record filled in, so a consumer holding just the device
  # value (e.g. after `attrValues`) still knows its own topic name and room
  # without re-deriving either from the nesting it came from.
  devices = builtins.mapAttrs (
    roomKey: devs:
    let
      room = rooms.${roomKey};
    in
    builtins.mapAttrs (devKey: d: d // {
      name = "${room.slug}_${devKey}";
      inherit room;
    }) devs
  ) rawDevices;

  # Flat list of every device value, for consumers that just need to iterate
  # all of them (e.g. generating z2m's IEEE -> friendly_name map) and don't
  # care about the room/device-key nesting.
  allDevices = builtins.concatLists (map builtins.attrValues (builtins.attrValues devices));
}
