# Lovelace dashboard, generated from the device registry.
#
# Cards are derived from `devices.nix` rather than hand-listed, so adding a
# device to the registry puts it on the dashboard in the right room with no
# edit here.
#
# The one thing that cannot be derived is the HA entity_id: it is anchored at
# first discovery and does NOT follow later zigbee2mqtt renames, so the
# devices that were registered under their old friendly names still answer to
# those ids (`light.light_1`, not `light.livingroom_light`). `entityBase`
# below is that mapping, keyed on IEEE address -- the one stable identifier --
# and is the *only* place the legacy names appear.
#
# To retire the table: delete a device in HA's UI, let z2m rediscover it, and
# it comes back as `<friendly_name>`; then drop its entry here. Not worth
# doing for its own sake -- it loses that entity's history.
{
  lib,
  ...
}:
let
  inherit (import ../../devices.nix) kinds rooms devices;

  # IEEE -> entity_id stem as actually registered in HA. Verified against
  # /var/lib/hass/.storage/core.entity_registry, not assumed from the name.
  entityBase = {
    "0x001788010ffdd431" = "light_1"; # livingroom_light
    "0x001788010f2c225a" = "light_2"; # kitchen_light
    "0x001788010f2c1a11" = "light_3"; # bedroom_light
    "0xa4c1385aef501143" = "plug_1"; # livingroom_plug_1
    "0xa4c13861447acbe2" = "plug_2"; # livingroom_plug_2
    "0xa4c1388762b9e41c" = "plug_3"; # livingroom_plug_3
    "0xa4c1388806d132cb" = "plug_4"; # kitchen_plug
    "0xa4c138ce243fe709" = "motion_sensor"; # kitchen_motion
    "0xa4c1381618f0f10c" = "button_1"; # livingroom_button
    "0xa4c138aa5aaccfa5" = "button_2"; # bedroom_button
    # Never got a friendly-name-based id; still addressed by raw IEEE.
    "0xa4c13880fa2af7d7" = "0xa4c13880fa2af7d7"; # bedroom_dial
    "0xa4c1380900f2ffff" = "0xa4c1380900f2ffff"; # kitchen_temp_probe
  };

  # Fail loudly at eval time rather than emitting a card pointing at an
  # entity that doesn't exist -- a silently dead card is easy to miss in the
  # UI and impossible to explain later.
  baseOf =
    d:
    entityBase.${d.id}
      or (throw "dashboard: device '${d.name}' (${d.id}) has no entityBase entry; look up its entity_id in core.entity_registry and add it");

  domainOf = d: if d.kind == kinds.light then "light" else "switch";
  entityOf = d: "${domainOf d}.${baseOf d}";

  # Sun-follow entity ids are built from the *label* passed to mkSunFollow
  # (HA slugifies "<device name> <entity name>"), which is why they read
  # `switch.plug_1_sun_follow_plug_1_sun_follow`. Kept as an explicit map for
  # the same reason as entityBase: derived slugification would be guesswork.
  sunFollow = {
    "0x001788010ffdd431" = "living_room_light_sun_follow_living_room_light";
    "0x001788010f2c1a11" = "bedroom_light_sun_follow_bedroom_light";
    "0xa4c1385aef501143" = "plug_1_sun_follow_plug_1";
    "0xa4c13861447acbe2" = "plug_2_sun_follow_plug_2";
    "0xa4c1388762b9e41c" = "plug_3_sun_follow_plug_3";
  };

  roomDevices = roomKey: builtins.attrValues devices.${roomKey};
  ofKind = kind: ds: builtins.filter (d: d.kind == kind) ds;

  # Turn `livingroom_plug_1` into `Plug 1` -- the room is already the heading.
  prettyName =
    d:
    let
      key = lib.removePrefix "${d.room.slug}_" d.name;
      words = builtins.filter builtins.isString (builtins.split "_" key);
    in
    lib.concatStringsSep " " (map (w: (lib.toUpper (builtins.substring 0 1 w)) + (builtins.substring 1 (-1) w)) words);

  tile = d: {
    type = "tile";
    entity = entityOf d;
    name = prettyName d;
  } // lib.optionalAttrs (d.kind == kinds.light) {
    features = [ { type = "light-brightness"; } ];
  };

  # Per-room section: lights and plugs as tiles, plus live power for any plug
  # that reports it.
  roomSection =
    roomKey:
    let
      ds = roomDevices roomKey;
      controllable = (ofKind kinds.light ds) ++ (ofKind kinds.plug ds);
      plugs = ofKind kinds.plug ds;
    in
    lib.optionals (controllable != [ ]) [
      {
        type = "grid";
        cards = [
          {
            type = "heading";
            heading = rooms.${roomKey}.label;
            heading_style = "title";
          }
        ] ++ (map tile controllable);
      }
    ]
    ++ lib.optionals (plugs != [ ]) [
      {
        type = "grid";
        cards = [
          {
            type = "heading";
            heading = "${rooms.${roomKey}.label} power";
            heading_style = "subtitle";
          }
        ]
        ++ (map (d: {
          type = "tile";
          entity = "sensor.${baseOf d}_power";
          name = prettyName d;
        }) plugs);
      }
    ];

  homeView = {
    title = "Home";
    path = "home";
    icon = "mdi:home";
    type = "sections";
    max_columns = 3;
    sections = builtins.concatMap roomSection (builtins.attrNames devices);
  };

  allDevices = builtins.concatMap roomDevices (builtins.attrNames devices);

  # Battery-powered things worth seeing at a glance, plus the environment
  # readings. Buttons/motion/sensors have no controllable entity, so they get
  # their own view rather than cluttering the room cards.
  sensorsView = {
    title = "Sensors";
    path = "sensors";
    icon = "mdi:motion-sensor";
    type = "sections";
    max_columns = 3;
    sections = [
      {
        type = "grid";
        cards = [
          {
            type = "heading";
            heading = "Environment";
            heading_style = "title";
          }
          {
            type = "tile";
            entity = "binary_sensor.motion_sensor_presence";
            name = "Kitchen presence";
          }
          {
            type = "tile";
            entity = "sensor.motion_sensor_illuminance";
            name = "Kitchen light level";
          }
          {
            type = "tile";
            entity = "sensor.0xa4c1380900f2ffff_temperature";
            name = "Kitchen temp probe";
          }
          {
            type = "tile";
            entity = "sensor.daylight_percentage";
            name = "Daylight";
          }
        ];
      }
      {
        type = "grid";
        cards = [
          {
            type = "heading";
            heading = "Batteries";
            heading_style = "title";
          }
        ]
        ++ map (d: {
          type = "tile";
          entity = "sensor.${baseOf d}_battery";
          name = "${d.room.label} ${prettyName d}";
        }) (builtins.filter (d: d.kind == kinds.button || d.kind == kinds.motion || d.kind == kinds.sensor) allDevices);
      }
    ];
  };

  # One section per sun-following device: the master toggle and the tuning
  # knobs that differ by kind (lights ramp a brightness curve, plugs flip at a
  # single sun-elevation threshold).
  sunFollowSection =
    d:
    let
      sf = sunFollow.${d.id};
      isLight = d.kind == kinds.light;
    in
    {
      type = "grid";
      cards = [
        {
          type = "heading";
          heading = "${d.room.label} ${prettyName d}";
          heading_style = "title";
        }
        {
          type = "tile";
          entity = "switch.${sf}_sun_follow";
          name = "Enabled";
        }
        {
          type = "tile";
          entity = "switch.${sf}_follow_sunrise";
          name = "Follow sunrise";
        }
        {
          type = "tile";
          entity = "switch.${sf}_follow_sunset";
          name = "Follow sunset";
        }
        {
          type = "tile";
          entity = "switch.${sf}_sun_follow_invert";
          name = "Invert";
        }
      ]
      ++ lib.optionals isLight [
        {
          type = "tile";
          entity = "switch.${sf}_sun_follow_can_turn_on";
          name = "Can turn on";
        }
        {
          type = "tile";
          entity = "number.${sf}_min_brightness";
          name = "Min brightness";
          features = [ { type = "numeric-input"; } ];
        }
        {
          type = "tile";
          entity = "number.${sf}_max_brightness";
          name = "Max brightness";
          features = [ { type = "numeric-input"; } ];
        }
        {
          type = "tile";
          entity = "number.${sf}_brightness_curve";
          name = "Curve";
          features = [ { type = "numeric-input"; } ];
        }
      ]
      ++ lib.optionals (!isLight) [
        {
          type = "tile";
          entity = "number.${sf}_sun_threshold";
          name = "Sun threshold";
          features = [ { type = "numeric-input"; } ];
        }
      ]
      ++ [
        {
          type = "tile";
          entity = "button.${sf}_sun_follow_reset";
          name = "Reset";
        }
      ];
    };

  sunFollowView = {
    title = "Sun-follow";
    path = "sun-follow";
    icon = "mdi:weather-sunset";
    type = "sections";
    max_columns = 3;
    sections = map sunFollowSection (builtins.filter (d: sunFollow ? ${d.id}) allDevices);
  };
in
{
  services.home-assistant.lovelaceConfig = {
    title = "Home";
    views = [
      homeView
      sensorsView
      sunFollowView
    ];
  };
}
