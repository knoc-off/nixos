# Lovelace dashboard, generated from the device registry.
#
# Cards are derived from `devices.nix` rather than hand-listed, so adding a
# device to the registry puts it on the dashboard in the right room with no
# edit here.
#
# Entity ids are derived too: the ha-entity-rename oneshot renames each
# light/plug's primary entity to `<domain>.<device name>` after HA starts, so
# `light.livingroom_light` is simply correct. HA would otherwise keep whatever
# id the entity was first discovered under (`light.light_1`) forever.
#
# Devices without a controllable primary (buttons, sensors) are still
# addressed by their discovered id -- they are not renamed, since only the
# primary matters for card addressing.
{
  lib,
  ...
}:
let
  inherit (import ../../devices.nix) kinds rooms devices;

  domainOf = d: if d.kind == kinds.light then "light" else "switch";
  entityOf = d: "${domainOf d}.${d.name}";

  # Sun-follow entity ids are built from the *label* passed to mkSunFollow
  # (HA slugifies "<device name> <entity name>"), which is why they read
  # `switch.plug_1_sun_follow_plug_1_sun_follow`. Kept as an explicit map for
  # the same reason as entityBase: derived slugification would be guesswork.
  # Sun-follow entities are named `<domain>.<device>_sun_follow_<suffix>` by
  # the ha-entity-rename oneshot, from the same device registry.
  sunFollowDevices = [
    devices.living-room.light
    devices.bedroom.light
    devices.living-room.plug_1
    devices.living-room.plug_2
    devices.living-room.plug_3
  ];

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
          entity = "sensor.${d.name}_power";
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
            entity = "binary_sensor.${devices.kitchen.motion.name}_presence";
            name = "Kitchen presence";
          }
          {
            type = "tile";
            entity = "sensor.${devices.kitchen.motion.name}_illuminance";
            name = "Kitchen light level";
          }
          {
            type = "tile";
            entity = "sensor.${devices.kitchen.temp_probe.name}_temperature";
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
          entity = "sensor.${d.name}_battery";
          name = "${d.room.label} ${prettyName d}";
        }) (builtins.filter (d: d.kind == kinds.button || d.kind == kinds.motion || d.kind == kinds.sensor) allDevices);
      }
    ];
  };

  # One section per sun-following device: the master toggle and the tuning
  # knobs that differ by kind (lights ramp a brightness curve, plugs flip at a
  # single sun-elevation threshold).
  #
  # Entity ids mirror the sun-follow unique_id suffixes from
  # mqtt-automations/default.nix, with kebab-case normalised to snake_case the
  # way HA slugifies them.
  sunFollowSection =
    d:
    let
      sf = suffix: "${d.name}_sun_follow_${suffix}";
      isLight = d.kind == kinds.light;
      toggle = suffix: label: {
        type = "tile";
        entity = "switch.${sf suffix}";
        name = label;
      };
      knob = suffix: label: {
        type = "tile";
        entity = "number.${sf suffix}";
        name = label;
        features = [ { type = "numeric-input"; } ];
      };
    in
    {
      type = "grid";
      cards = [
        {
          type = "heading";
          heading = "${d.room.label} ${prettyName d}";
          heading_style = "title";
        }
        (toggle "enabled" "Enabled")
        (toggle "follow_sunrise" "Follow sunrise")
        (toggle "follow_sunset" "Follow sunset")
        (toggle "invert" "Invert")
      ]
      ++ lib.optionals isLight [
        (toggle "allow_wake" "Can turn on")
        (knob "min_brightness" "Min brightness")
        (knob "max_brightness" "Max brightness")
        (knob "gamma" "Curve")
      ]
      ++ lib.optionals (!isLight) [
        (knob "threshold" "Sun threshold")
      ]
      ++ [
        {
          type = "tile";
          entity = "button.${sf "reset"}";
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
    sections = map sunFollowSection sunFollowDevices;
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
