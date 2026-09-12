# MQTT automations -- Rust binaries from pkgs/mqtt-automations.
# Config via environment variables. HA number/switch entities are wired
# directly to the retained MQTT topics (native `mqtt:` platform) — no
# custom sync automations needed.
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  mqttPkg = self.packages.${pkgs.stdenv.hostPlatform.system}.mqtt-automations;

  mkAutomation =
    {
      name,
      bin,
      description ? "MQTT automation: ${name}",
      env ? { },
    }:
    {
      "mqtt-auto-${name}" = {
        inherit description;
        after = [
          "mosquitto.service"
          "network-online.target"
        ];
        wants = [
          "mosquitto.service"
          "network-online.target"
        ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          ExecStart = "${mqttPkg}/bin/${bin}";
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

  # MQTT topics for HA-controlled settings
  startTimeTopic = "mqtt-auto/sunrise-lights/start-time";
  durationTopic = "mqtt-auto/sunrise-lights/duration";
  maxBrightnessTopic = "mqtt-auto/sunrise-lights/max-brightness";
  gammaTopic = "mqtt-auto/sunrise-lights/gamma";
  hueEnabledTopic = "mqtt-auto/color-temp-cycle/enabled";

  # Location for color-temp-cycle, which genuinely tracks the real sun.
  # sunrise-lights deliberately does not — it runs on a fixed clock.
  sunEnv = {
    LATITUDE = "52.52";
    LONGITUDE = "13.405";
  };

  # Service definitions

  automations = [
    {
      name = "cat-doorbell";
      bin = "cat-doorbell";
      description = "Notify phone on motion detection (cat doorbell)";
      env = {
        SENSOR_TOPIC = "zigbee2mqtt/motion_sensor";
        NTFY_URL = "https://ntfy.niko.ink";
        NTFY_TOPIC = "cat-doorbell";
        COOLDOWN_SECONDS = "300";
        NOTIFICATION_TITLE = "Cat Doorbell";
        NTFY_TOKEN_FILE = config.sops.secrets."services/ntfy/publish-token".path;
        CURL_BIN = "${pkgs.curl}/bin/curl";
      };
    }
    {
      name = "sunrise-lights";
      bin = "sunrise-lights";
      description = "Wake-up light: smooth brightness ramp on a fixed schedule";
      env = {
        LIGHT_TOPIC = "zigbee2mqtt/light_3/set";
        UPDATE_INTERVAL = "30";
        MAX_BRIGHTNESS = "30";
        START_TIME = "06:30:00";
        DURATION = "45";
        START_TIME_TOPIC = startTimeTopic;
        DURATION_TOPIC = durationTopic;
        MAX_BRIGHTNESS_TOPIC = maxBrightnessTopic;
        GAMMA_TOPIC = gammaTopic;
      };
    }
    {
      name = "bedtime-button";
      bin = "bedtime-button";
      description = "button_2: time-aware low-light toggle for light_3, hold for auto-off";
      env = {
        BUTTON_TOPIC = "zigbee2mqtt/button_2/action";
        LIGHT_TOPIC = "zigbee2mqtt/light_3/set";
        LOW_BRIGHTNESS = "25";
        DAY_BRIGHTNESS = "254";
        EVENING_START_HOUR = "21";
        DAY_START_HOUR = "6";
        HOLD_OFF_MINUTES = "5";
      };
    }
    {
      name = "color-temp-cycle";
      bin = "color-temp-cycle";
      description = "Adjust light color temperature through the day";
      env = sunEnv // {
        LIGHT_TOPIC = "zigbee2mqtt/light_3/set";
        CT_WARM = "454";
        CT_COOL = "250";
        UPDATE_INTERVAL = "60";
        ENABLED_TOPIC = hueEnabledTopic;
      };
    }
    {
      name = "color-temp-cycle-living-room";
      bin = "color-temp-cycle";
      description = "Adjust living room light color temperature through the day";
      env = sunEnv // {
        MQTT_CLIENT_ID = "color-temp-cycle-living-room";
        LIGHT_TOPIC = "zigbee2mqtt/light_1/set";
        CT_WARM = "454";
        CT_COOL = "250";
        UPDATE_INTERVAL = "60";
        ENABLED_TOPIC = hueEnabledTopic;
      };
    }
    {
      name = "button-dispatcher";
      bin = "button-dispatcher";
      description = "button_1: single toggles light_1, double/hold toggles the living-room group";
      env = {
        BUTTON_TOPIC = "zigbee2mqtt/button_1/action";
        SINGLE_TOPICS = "zigbee2mqtt/light_1/set";
        GROUP_TOPICS = "zigbee2mqtt/light_1/set,zigbee2mqtt/plug_1/set,zigbee2mqtt/plug_2/set,zigbee2mqtt/plug_3/set";
      };
    }
  ];

  allServices = lib.mergeAttrsList (map mkAutomation automations);
in
{
  systemd.services = allServices;

  services.home-assistant.config = {
    # Native MQTT number/switch entities, bound directly to the retained
    # topics the Rust daemons read via Runtime::setting. Replaces the old
    # input_number/input_boolean + 8 hand-written sync automations.
    mqtt.time = [
      {
        unique_id = "sunrise_start_time";
        name = "Sunrise start time";
        command_topic = startTimeTopic;
        state_topic = startTimeTopic;
        retain = true;
        icon = "mdi:clock-start";
      }
    ];

    mqtt.number = [
      {
        unique_id = "sunrise_duration";
        name = "Sunrise duration";
        command_topic = durationTopic;
        state_topic = durationTopic;
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
        command_topic = maxBrightnessTopic;
        state_topic = maxBrightnessTopic;
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
        command_topic = gammaTopic;
        state_topic = gammaTopic;
        retain = true;
        min = 0.5;
        max = 4.0;
        step = 0.1;
        icon = "mdi:speedometer";
        mode = "slider";
      }
    ];

    mqtt.switch = [
      {
        unique_id = "lights_follow_hue";
        name = "Lights follow hue";
        command_topic = hueEnabledTopic;
        state_topic = hueEnabledTopic;
        retain = true;
        payload_on = "true";
        payload_off = "false";
        icon = "mdi:palette";
      }
    ];
  };
}
