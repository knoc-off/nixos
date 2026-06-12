# MQTT automations -- Rust binaries from pkgs/mqtt-automations.
# Config via environment variables; buttons get a generated JSON file.
# HA sliders are bridged bidirectionally to MQTT retained topics via mkMqttSlider.
{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  mqttPkg = self.packages.${pkgs.stdenv.hostPlatform.system}.mqtt-automations;

  # -- helpers -----------------------------------------------------------------

  mkAutomation = {
    name,
    bin,
    description ? "MQTT automation: ${name}",
    env ? {},
    args ? [],
  }: {
    "mqtt-auto-${name}" = {
      inherit description;
      after = ["mosquitto.service" "network-online.target"];
      wants = ["mosquitto.service" "network-online.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart =
          "${mqttPkg}/bin/${bin}"
          + lib.optionalString (args != []) (" " + lib.concatStringsSep " " args);
        Restart = "always";
        RestartSec = "10s";
        Environment = lib.mapAttrsToList (k: v: ''"${k}=${v}"'') env;
      };
      unitConfig = {
        StartLimitIntervalSec = 300;
        StartLimitBurst = 20;
      };
    };
  };

  # Bidirectional HA slider ↔ MQTT retained topic.
  # Generates an input_number + two automations (forward: HA→MQTT, reverse: MQTT→HA).
  mkMqttSlider = {
    entity,
    name,
    topic,
    min ? 0,
    max ? 100,
    step ? 1,
    unit ? "",
    icon ? "mdi:tune",
    initial ? 0,
    float ? false,
  }: let
    filter = if float then "float" else "int";
  in {
    input_number.${entity} = {
      inherit name min max step initial icon;
      mode = "slider";
      unit_of_measurement = unit;
    };
    automation = [
      {
        id = "${entity}_to_mqtt";
        alias = "Sync ${name} to MQTT";
        mode = "single";
        trigger = [
          {
            platform = "state";
            entity_id = "input_number.${entity}";
          }
        ];
        action = [
          {
            service = "mqtt.publish";
            data = {
              inherit topic;
              retain = true;
              payload = "{{ states('input_number.${entity}') | ${filter} }}";
            };
          }
        ];
      }
      {
        id = "${entity}_from_mqtt";
        alias = "Sync ${name} from MQTT";
        mode = "single";
        trigger = [
          {
            platform = "mqtt";
            inherit topic;
          }
        ];
        condition = [
          {
            condition = "template";
            value_template = "{{ trigger.payload | ${filter} != states('input_number.${entity}') | ${filter} }}";
          }
        ];
        action = [
          {
            service = "input_number.set_value";
            target.entity_id = "input_number.${entity}";
            data.value = "{{ trigger.payload | ${filter} }}";
          }
        ];
      }
    ];
  };

  # Bidirectional HA toggle ↔ MQTT retained topic.
  # Generates an input_boolean + two automations (forward: HA→MQTT, reverse: MQTT→HA).
  mkMqttToggle = {
    entity,
    name,
    topic,
    icon ? "mdi:toggle-switch",
    initial ? false,
  }: {
    input_boolean.${entity} = {
      inherit name initial icon;
    };
    automation = [
      {
        id = "${entity}_to_mqtt";
        alias = "Sync ${name} to MQTT";
        mode = "single";
        trigger = [
          {
            platform = "state";
            entity_id = "input_boolean.${entity}";
          }
        ];
        action = [
          {
            service = "mqtt.publish";
            data = {
              inherit topic;
              retain = true;
              payload = "{{ states('input_boolean.${entity}') }}";
            };
          }
        ];
      }
      {
        id = "${entity}_from_mqtt";
        alias = "Sync ${name} from MQTT";
        mode = "single";
        trigger = [
          {
            platform = "mqtt";
            inherit topic;
          }
        ];
        condition = [
          {
            condition = "template";
            value_template = "{{ trigger.payload != states('input_boolean.${entity}') }}";
          }
        ];
        action = [
          {
            service = "input_boolean.turn_{{ trigger.payload }}";
            target.entity_id = "input_boolean.${entity}";
          }
        ];
      }
    ];
  };

  mergeHaConfigs = lib.foldl' (acc: c: {
    input_number = acc.input_number // (c.input_number or {});
    input_boolean = acc.input_boolean // (c.input_boolean or {});
    automation = acc.automation ++ (c.automation or []);
  }) {input_number = {}; input_boolean = {}; automation = [];};

  # -- MQTT topics for HA-controlled settings ----------------------------------

  delayTopic = "mqtt-auto/sunrise-lights/delay";
  maxBrightnessTopic = "mqtt-auto/sunrise-lights/max-brightness";
  gammaTopic = "mqtt-auto/sunrise-lights/gamma";
  hueEnabledTopic = "mqtt-auto/color-temp-cycle/enabled";

  # -- button config -----------------------------------------------------------

  buttonConfig = pkgs.writeText "button-dispatcher.json" (builtins.toJSON {
    buttons = {
      "zigbee2mqtt/button_1/action" = {
        single = {
          topic = "zigbee2mqtt/light_1/set";
          payload = {state = "TOGGLE";};
        };
        double = {
          topic = "zigbee2mqtt/light_1/set";
          payload = {brightness = 254;};
        };
        hold = {
          topic = "zigbee2mqtt/light_1/set";
          payload = {state = "OFF";};
        };
      };
    };
  });

  # -- service definitions -----------------------------------------------------

  automations = [
    {
      name = "plug-auto-off";
      bin = "plug-auto-off";
      description = "Auto-set 1hr countdown when plug turns on";
      env = {
        PLUG_TOPIC = "zigbee2mqtt/plug_1";
        COUNTDOWN_SECONDS = "3600";
      };
    }
    {
      name = "cat-doorbell";
      bin = "cat-doorbell";
      description = "Notify phone on motion detection (cat doorbell)";
      env = {
        SENSOR_TOPIC = "zigbee2mqtt/motion_sensor";
        HA_URL = "http://localhost:8123";
        NOTIFY_SERVICES = "notify.mobile_app_pixel_10,notify.mobile_app_pixelsticks2,notify.mobile_app_pixel_7a,notify.mobile_app_eileens_iphone";
        COOLDOWN_SECONDS = "300";
        NOTIFICATION_TITLE = "Cat Doorbell";
        HA_TOKEN_FILE = config.sops.secrets."ha/api_token".path;
      };
    }
    {
      name = "sunrise-lights";
      bin = "sunrise-lights";
      description = "Gradually turn on lights at sunrise";
      env = {
        LIGHT_TOPIC = "zigbee2mqtt/light_3/set";
        LATITUDE = "52.52";
        LONGITUDE = "13.405";
        RAMP_MINUTES = "60";
        OFFSET_MINUTES = "0";
        UPDATE_INTERVAL = "30";
        COLOR_TEMP_START = "454";
        COLOR_TEMP_END = "250";
        TIMEZONE = "Europe/Berlin";
        ELEVATION_END = "11";
        MAX_BRIGHTNESS = "30";
        DELAY_TOPIC = delayTopic;
        MAX_BRIGHTNESS_TOPIC = maxBrightnessTopic;
        GAMMA_TOPIC = gammaTopic;
      };
    }
    {
      name = "button-dispatcher";
      bin = "button-dispatcher";
      description = "Button action dispatcher";
      args = ["${buttonConfig}"];
    }
    {
      name = "color-temp-cycle";
      bin = "color-temp-cycle";
      description = "Adjust light color temperature through the day";
      env = {
        LIGHT_TOPIC = "zigbee2mqtt/light_3/set";
        LATITUDE = "52.52";
        LONGITUDE = "13.405";
        CT_WARM = "454";
        CT_COOL = "250";
        UPDATE_INTERVAL = "60";
        TIMEZONE = "Europe/Berlin";
        ENABLED_TOPIC = hueEnabledTopic;
      };
    }
    {
      name = "color-temp-cycle-living-room";
      bin = "color-temp-cycle";
      description = "Adjust living room light color temperature through the day";
      env = {
        MQTT_CLIENT_ID = "color-temp-cycle-living-room";
        LIGHT_TOPIC = "zigbee2mqtt/light_1/set";
        LATITUDE = "52.52";
        LONGITUDE = "13.405";
        CT_WARM = "454";
        CT_COOL = "250";
        UPDATE_INTERVAL = "60";
        TIMEZONE = "Europe/Berlin";
        ENABLED_TOPIC = hueEnabledTopic;
      };
    }
  ];

  allServices = lib.foldl' (acc: def: acc // (mkAutomation def)) {} automations;
in {
  systemd.services = allServices;

  services.home-assistant.config = mergeHaConfigs [
    (mkMqttSlider {
      entity = "sunrise_delay_minutes";
      name = "Sunrise delay";
      topic = delayTopic;
      max = 180;
      step = 15;
      unit = "min";
      icon = "mdi:sleep";
    })
    (mkMqttSlider {
      entity = "sunrise_max_brightness";
      name = "Sunrise max brightness";
      topic = maxBrightnessTopic;
      max = 100;
      step = 5;
      unit = "%";
      icon = "mdi:brightness-percent";
      initial = 30;
    })
    (mkMqttSlider {
      entity = "sunrise_ramp_speed";
      name = "Sunrise ramp speed";
      topic = gammaTopic;
      min = 0.5;
      max = 4.0;
      step = 0.1;
      icon = "mdi:speedometer";
      initial = 2.0;
      float = true;
    })
    (mkMqttToggle {
      entity = "lights_follow_hue";
      name = "Lights follow hue";
      topic = hueEnabledTopic;
      icon = "mdi:palette";
      initial = true;
    })
  ];
}
