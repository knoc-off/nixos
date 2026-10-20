# Home Assistant side of the lighting service: per-bulb tuning knobs, a
# "release" button and a mode sensor, plus the house-wide colour and wake
# settings the room scripts read (see pkgs/mqtt-automations/src/prelude.lua).
#
# Identity is inherited from the old per-device sun-follow daemons on
# purpose: unique_ids stay `sun_follow_<ieee>_<suffix>` and the HA device
# `sun-follow-<ieee>`, so existing knob values, entity_ids and history carry
# over, and ha-entity-rename / ha-registry-gc keep covering them unchanged.
# Knobs that no longer exist (enabled, follow sunrise/sunset, can turn on,
# reset) are dropped from the registry by ha-registry-gc.
#
# Topics are the old ones too (`mqtt-auto/sun-follow/<device>/...`), which is
# what the scripts read.
{
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../../devices.nix) lit kinds;

  # Lights get a brightness curve, plugs a daylight threshold.
  lamps = builtins.concatLists (
    lib.mapAttrsToList (
      roomKey: ds:
      lib.mapAttrsToList (key: d: d // { inherit key roomKey; }) ds
    ) lit
  );
  lights = builtins.filter (d: d.kind == kinds.light) lamps;
  plugs = builtins.filter (d: d.kind == kinds.plug) lamps;

  label = d: "${d.room.label} ${builtins.replaceStrings [ "_" ] [ " " ] d.key}";
  knobTopic = d: suffix: "mqtt-auto/sun-follow/${d.name}/${suffix}";

  device = d: {
    identifiers = [ "sun-follow-${d.id}" ];
    name = "${label d} (lighting)";
  };

  number =
    d: suffix: name: icon:
    {
      min,
      max,
      step,
      unit ? "%",
    }:
    {
      unique_id = "sun_follow_${d.id}_${suffix}";
      name = "${label d} ${name}";
      inherit icon min max step;
      unit_of_measurement = unit;
      mode = "slider";
      command_topic = knobTopic d suffix;
      state_topic = knobTopic d suffix;
      retain = true;
      entity_category = "config";
      device = device d;
    };

  # Defaults must match the setting() defaults in the prelude: they only
  # seed topics that have nothing retained yet, so HA shows a value instead
  # of "unknown" (see `seed` below).
  lightKnobs = d: [
    {
      entity = number d "min-brightness" "min brightness" "mdi:brightness-4" {
        min = 0;
        max = 100;
        step = 5;
      };
      default = 5;
    }
    {
      entity = number d "max-brightness" "max brightness" "mdi:brightness-7" {
        min = 0;
        max = 100;
        step = 5;
      };
      default = 100;
    }
    {
      entity = number d "gamma" "brightness curve" "mdi:chart-bell-curve" {
        min = 0.3;
        max = 3.0;
        step = 0.1;
        unit = "";
      };
      default = 1;
    }
  ];
  plugKnobs = d: [
    {
      entity = number d "threshold" "sun threshold" "mdi:brightness-6" {
        min = 0;
        max = 100;
        step = 5;
      };
      default = 15;
    }
  ];
  knobs = builtins.concatMap lightKnobs lights ++ builtins.concatMap plugKnobs plugs;

  plugSwitches = map (d: {
    unique_id = "sun_follow_${d.id}_invert";
    name = "${label d} invert";
    icon = "mdi:swap-vertical";
    command_topic = knobTopic d "invert";
    state_topic = knobTopic d "invert";
    retain = true;
    payload_on = "true";
    payload_off = "false";
    entity_category = "config";
    device = device d;
  }) plugs;

  stateTopic = d: "lights/${d.roomKey}/${d.key}/state";

  releaseButtons = map (d: {
    unique_id = "sun_follow_${d.id}_release";
    name = "${label d} release";
    icon = "mdi:hand-back-left-off";
    command_topic = "lights/${d.roomKey}/${d.key}/release";
    payload_press = "release";
    device = device d;
  }) lamps
  ++ [
    {
      unique_id = "lights_release_all";
      name = "Release all lights";
      icon = "mdi:restore";
      command_topic = "lights/release";
      payload_press = "release";
    }
  ];

  modeSensors = map (d: {
    unique_id = "sun_follow_${d.id}_mode";
    name = "${label d} mode";
    icon = "mdi:account-hard-hat";
    state_topic = stateTopic d;
    value_template = "{{ value_json.mode }}";
    device = device d;
  }) lamps;

  sunrise = suffix: "mqtt-auto/sunrise-lights/${suffix}";
  colorTempTopic = "mqtt-auto/color-temp-cycle/enabled";

  # Room controls (see `lights/<room>/...` in the prelude). Entity ids come
  # from the names (`select.bedroom_scene`), which the Rooms dashboard view
  # relies on. `lights` publishes JSON, so strings arrive quoted.
  roomTopic = roomKey: suffix: "lights/${roomKey}/${suffix}";
  roomKeys = builtins.filter (r: lit.${r} != { }) (builtins.attrNames lit);
  roomLabel = roomKey: (import ../../devices.nix).rooms.${roomKey}.label;
  jsonValue = "{{ value | from_json }}";

  roomScenes = map (r: {
    unique_id = "lights_${r}_scene";
    name = "${roomLabel r} scene";
    icon = "mdi:palette-swatch";
    command_topic = roomTopic r "scene";
    command_template = "{{ value | to_json }}";
    state_topic = roomTopic r "scene";
    value_template = jsonValue;
    options = [
      "auto"
      "bright"
      "dim"
      "night"
    ];
  }) roomKeys;

  roomAutomatic = map (r: {
    unique_id = "lights_${r}_automatic";
    name = "${roomLabel r} automatic";
    icon = "mdi:motion-sensor";
    command_topic = roomTopic r "automatic";
    state_topic = roomTopic r "automatic";
    retain = true;
    payload_on = "true";
    payload_off = "false";
  }) roomKeys;

  roomRelease = map (r: {
    unique_id = "lights_${r}_release";
    name = "${roomLabel r} release";
    icon = "mdi:hand-back-left-off";
    command_topic = roomTopic r "release";
    payload_press = "release";
  }) roomKeys;

  roomMode = map (r: {
    unique_id = "lights_${r}_mode";
    name = "${roomLabel r} mode";
    icon = "mdi:account-hard-hat";
    state_topic = roomTopic r "mode";
    value_template = jsonValue;
  }) roomKeys;

  # Only rooms whose script runs occupancy() publish this.
  roomOccupied = map (r: {
    unique_id = "lights_${r}_occupied";
    name = "${roomLabel r} occupied";
    device_class = "occupancy";
    state_topic = roomTopic r "occupied";
    payload_on = "true";
    payload_off = "false";
  }) roomKeys;

  # A room runs only while both its own switch and this one are on.
  houseAutomatic = {
    unique_id = "lights_house_automatic";
    name = "House automatic";
    icon = "mdi:home-automation";
    command_topic = "lights/automatic";
    state_topic = "lights/automatic";
    retain = true;
    payload_on = "true";
    payload_off = "false";
  };

  seeds =
    map (k: {
      topic = k.entity.command_topic;
      value = toString k.default;
    }) knobs
    ++ map (s: {
      topic = s.command_topic;
      value = "false";
    }) plugSwitches
    ++ map (s: {
      topic = s.command_topic;
      value = "true";
    }) (roomAutomatic ++ [ houseAutomatic ]);

  seed = pkgs.writeShellApplication {
    name = "lighting-seed";
    runtimeInputs = [ pkgs.mosquitto ];
    text = ''
      # A retained message arrives at once if there is one; a timeout means
      # the topic is empty.
      ${lib.concatMapStringsSep "\n" (s: ''
        if ! mosquitto_sub -t ${lib.escapeShellArg s.topic} -C 1 -W 2 >/dev/null 2>&1; then
          echo "seeding ${s.topic} = ${s.value}"
          mosquitto_pub -r -t ${lib.escapeShellArg s.topic} -m ${lib.escapeShellArg s.value}
        fi
      '') seeds}
    '';
  };
in
{
  systemd.services.lighting-seed = {
    description = "Seed empty lighting settings topics with their defaults";
    after = [ "mosquitto.service" ];
    requires = [ "mosquitto.service" ];
    before = [ "lights.service" ];
    wantedBy = [ "lights.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe seed;
      DynamicUser = true;
    };
  };

  services.home-assistant.config = {
    mqtt.number = map (k: k.entity) knobs ++ [
      {
        unique_id = "sunrise_duration";
        name = "Sunrise duration";
        command_topic = sunrise "duration";
        state_topic = sunrise "duration";
        retain = true;
        min = 10;
        max = 120;
        step = 5;
        unit_of_measurement = "min";
        icon = "mdi:timer-sand";
        mode = "slider";
      }
      {
        unique_id = "sunrise_max_brightness";
        name = "Sunrise max brightness";
        command_topic = sunrise "max-brightness";
        state_topic = sunrise "max-brightness";
        retain = true;
        min = 0;
        max = 100;
        step = 5;
        unit_of_measurement = "%";
        icon = "mdi:brightness-percent";
        mode = "slider";
      }
      {
        unique_id = "sunrise_ramp_speed";
        name = "Sunrise ramp speed";
        command_topic = sunrise "gamma";
        state_topic = sunrise "gamma";
        retain = true;
        min = 0.5;
        max = 4.0;
        step = 0.1;
        icon = "mdi:speedometer";
        mode = "slider";
      }
    ];

    mqtt.time = [
      {
        unique_id = "sunrise_start_time";
        name = "Sunrise start time";
        command_topic = sunrise "start-time";
        state_topic = sunrise "start-time";
        retain = true;
        icon = "mdi:clock-start";
      }
    ];

    mqtt.switch = plugSwitches ++ roomAutomatic ++ [
      houseAutomatic
      {
        unique_id = "lights_follow_hue";
        name = "Lights follow hue";
        command_topic = colorTempTopic;
        state_topic = colorTempTopic;
        retain = true;
        payload_on = "true";
        payload_off = "false";
        icon = "mdi:palette";
      }
    ];

    mqtt.button = releaseButtons ++ roomRelease;
    mqtt.sensor = modeSensors ++ roomMode;
    mqtt.select = roomScenes;
    mqtt.binary_sensor = roomOccupied;
  };
}
