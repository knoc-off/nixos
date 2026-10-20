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
  inherit (import ../../devices.nix) kinds rooms devices lit zigbeeGroups roomOrder;

  domainOf = d: if d.kind == kinds.light then "light" else "switch";
  entityOf = d: "${domainOf d}.${d.name}";

  # Lighting entities are named `<domain>.<device>_sun_follow_<suffix>` by
  # the ha-entity-rename oneshot (their unique_ids predate the lighting
  # service, see services/lighting/home-assistant.nix).
  litDevices = builtins.concatMap (r: builtins.attrValues (lit.${r} or { })) roomOrder;

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
    sections = builtins.concatMap roomSection roomOrder;
  };

  allDevices = builtins.concatMap roomDevices roomOrder;

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
            entity = "binary_sensor.${devices.kitchen.motion.name}_occupancy";
            name = "Kitchen presence";
          }
          {
            type = "tile";
            entity = "sensor.${devices.kitchen.motion.name}_illumination";
            name = "Kitchen light level";
          }
          {
            type = "tile";
            entity = "sensor.${devices.kitchen.temp_probe.name}_temperature";
            name = "Kitchen temp probe";
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
        }) (builtins.filter (d: d.kind == kinds.button || d.kind == kinds.motion || d.kind == kinds.sensor || d.kind == kinds.door) allDevices);
      }
    ];
  };

  # One section per lit device: who is in charge (auto or held), a button to
  # hand it back, and the tuning knobs that differ by kind (lights ramp a
  # brightness curve, plugs flip at a daylight threshold).
  #
  # Entity ids mirror the unique_id suffixes from
  # services/lighting/home-assistant.nix, with kebab-case normalised to
  # snake_case the way HA slugifies them.
  lightingSection =
    d:
    let
      sf = suffix: "${d.name}_sun_follow_${suffix}";
      isLight = d.kind == kinds.light;
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
        {
          type = "tile";
          entity = "sensor.${sf "mode"}";
          name = "Mode";
        }
        {
          type = "tile";
          entity = "button.${sf "release"}";
          name = "Release";
        }
      ]
      ++ lib.optionals isLight [
        (knob "min_brightness" "Min brightness")
        (knob "max_brightness" "Max brightness")
        (knob "gamma" "Curve")
      ]
      ++ lib.optionals (!isLight) [
        (knob "threshold" "Sun threshold")
        {
          type = "tile";
          entity = "switch.${sf "invert"}";
          name = "Invert";
        }
      ];
    };

  lightingView = {
    title = "Lighting";
    path = "sun-follow";
    icon = "mdi:weather-sunset";
    type = "sections";
    max_columns = 3;
    sections = [
      {
        type = "grid";
        cards = [
          {
            type = "heading";
            heading = "House";
            heading_style = "title";
          }
          {
            type = "tile";
            entity = "switch.lights_follow_hue";
            name = "Colour follows the sun";
          }
          {
            type = "tile";
            entity = "time.sunrise_start_time";
            name = "Wake at";
          }
          {
            type = "tile";
            entity = "number.sunrise_duration";
            name = "Wake duration";
          }
          {
            type = "tile";
            entity = "number.sunrise_max_brightness";
            name = "Wake brightness";
          }
        ];
      }
    ]
    ++ map lightingSection litDevices;
  };

  # Each room as one unit: the whole room's light (its zigbee group, or its
  # only bulb) with brightness and colour, then the room controls from
  # services/lighting/home-assistant.nix, then the bulbs without sliders.
  # Not the default view yet: Home stays first.
  roomCard =
    roomKey:
    let
      ds = builtins.attrValues lit.${roomKey};
      room = rooms.${roomKey};
      group = lib.findFirst (g: zigbeeGroups.${g}.room == roomKey) null (builtins.attrNames zigbeeGroups);
      lamps = ofKind kinds.light ds;
      main =
        if group != null then
          "light.${group}"
        else if builtins.length lamps == 1 then
          entityOf (builtins.head lamps)
        else
          null;
      # Matches the names in lighting/home-assistant.nix, slugified.
      ctl = domain: suffix: "${domain}.${lib.toLower (builtins.replaceStrings [ " " ] [ "_" ] room.label)}_${suffix}";
      hasOccupancy = builtins.elem roomKey occupancyRooms;
    in
    {
      type = "grid";
      cards = [
        {
          type = "heading";
          heading = room.label;
          heading_style = "title";
        }
      ]
      ++ lib.optional (main != null) {
        type = "tile";
        entity = main;
        name = "${room.label} lights";
        grid_options.columns = "full";
        features = [
          { type = "light-brightness"; }
          { type = "light-color-temp"; }
        ];
      }
      ++ [
        {
          type = "tile";
          entity = ctl "select" "scene";
          name = "Scene";
          grid_options.columns = "full";
          features = [
            {
              type = "select-options";
            }
          ];
        }
      ]
      ++ lib.optional hasOccupancy {
        type = "tile";
        entity = ctl "binary_sensor" "occupied";
        name = "Occupied";
      }
      ++ [
        {
          type = "tile";
          entity = ctl "sensor" "mode";
          name = "Mode";
        }
      ]
      ++ lib.optional hasOccupancy {
        type = "tile";
        entity = ctl "switch" "automatic";
        name = "Automatic";
      }
      ++ [
        {
          type = "tile";
          entity = ctl "button" "release";
          name = "Reset";
        }
      ]
      ++ map (d: {
        type = "tile";
        entity = entityOf d;
        name = prettyName d;
        vertical = true;
        grid_options.columns = 4;
      }) (if main != null && group == null then [ ] else ds);
    };

  # Rooms whose script uses occupancy(): only those publish `occupied` and
  # have anything for the automatic switch to turn off.
  occupancyRooms = [
    "living-room"
    "kitchen"
    "bedroom"
    "bathroom"
    "hallway"
  ];

  roomsView = {
    title = "Rooms";
    path = "rooms";
    icon = "mdi:floor-plan";
    type = "sections";
    max_columns = 3;
    sections = [
      {
        type = "grid";
        cards = [
          {
            type = "heading";
            heading = "House";
            heading_style = "title";
          }
          {
            type = "tile";
            entity = "switch.house_automatic";
            name = "Automatic";
          }
          {
            type = "tile";
            entity = "button.release_all_lights";
            name = "Reset all";
          }
        ];
      }
    ]
    ++ map roomCard (builtins.filter (r: (lit.${r} or { }) != { }) roomOrder);
  };
in
{
  services.home-assistant.lovelaceConfig = {
    title = "Home";
    views = [
      roomsView
      homeView
      sensorsView
      lightingView
    ];
  };
}
