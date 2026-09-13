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

  # -- sun-follow: generic sun-tracking dimmer/switch, one instance per device --
  #
  # Extending a device with sun-following is just adding an entry to
  # `sunFollowDevices` below — the systemd service and HA entities are both
  # generated from it, so no other file needs to change.
  daylightSensorTopic = "mqtt-auto/sun-follow/daylight-pct";

  mkSunFollow =
    {
      device, # zigbee2mqtt friendly name, e.g. "light_1"
      mode, # "brightness" (dimmable light) or "switch" (on/off plug)
      label, # display name for HA, e.g. "Living room light"
      defaultFollowSunrise ? true,
      defaultFollowSunset ? true,
      defaultMin ? 1,
      defaultMax ? 100,
      defaultGamma ? 1.0,
      # Normalized daylight %, not raw sun elevation -- see the writeup in
      # git history for why. 15% lands within ~40min of true sunset/sunrise
      # year-round at Berlin's latitude; the seasonal drift below that is
      # negligible.
      defaultThreshold ? 15,
      publishDaylightSensor ? false, # only one instance needs to -- see daylightSensorTopic
    }:
    let
      base = "mqtt-auto/sun-follow/${device}";
      t = suffix: "${base}/${suffix}";
      isSwitch = mode == "switch";

      env = sunEnv // {
        MQTT_CLIENT_ID = "sun-follow-${device}";
        DEVICE_TOPIC = "zigbee2mqtt/${device}/set";
        MODE = mode;
        ENABLED_TOPIC = t "enabled";
        FOLLOW_SUNRISE_TOPIC = t "follow-sunrise";
        FOLLOW_SUNSET_TOPIC = t "follow-sunset";
        INVERT_TOPIC = t "invert";
        RESET_TOPIC = t "reset";
        FOLLOW_SUNRISE = lib.boolToString defaultFollowSunrise;
        FOLLOW_SUNSET = lib.boolToString defaultFollowSunset;
      }
      // lib.optionalAttrs (!isSwitch) {
        ALLOW_WAKE_TOPIC = t "allow-wake";
        MIN_BRIGHTNESS_TOPIC = t "min-brightness";
        MAX_BRIGHTNESS_TOPIC = t "max-brightness";
        GAMMA_TOPIC = t "gamma";
        MIN_BRIGHTNESS = toString defaultMin;
        MAX_BRIGHTNESS = toString defaultMax;
        GAMMA = toString defaultGamma;
      }
      // lib.optionalAttrs isSwitch {
        THRESHOLD_TOPIC = t "threshold";
        THRESHOLD = toString defaultThreshold;
      }
      // lib.optionalAttrs publishDaylightSensor {
        DAYLIGHT_SENSOR_TOPIC = daylightSensorTopic;
      };

      deviceInfo = {
        identifiers = [ "sun-follow-${device}" ];
        name = "${label} (sun-follow)";
      };

      mkSwitch = suffix: name: icon: {
        unique_id = "sun_follow_${device}_${suffix}";
        inherit name icon;
        command_topic = t suffix;
        state_topic = t suffix;
        retain = true;
        payload_on = "true";
        payload_off = "false";
        device = deviceInfo;
      };

      mkNumber =
        suffix: name: icon:
        {
          min,
          max,
          step ? 1,
          unit ? "%",
        }:
        {
          unique_id = "sun_follow_${device}_${suffix}";
          inherit name icon min max step;
          unit_of_measurement = unit;
          mode = "slider";
          command_topic = t suffix;
          state_topic = t suffix;
          retain = true;
          device = deviceInfo;
        };

      mkButton = suffix: name: icon: {
        unique_id = "sun_follow_${device}_${suffix}";
        inherit name icon;
        command_topic = t suffix;
        payload_press = "reset";
        device = deviceInfo;
      };

      switches = [
        (mkSwitch "enabled" "${label} sun-follow" "mdi:sun-clock")
        (mkSwitch "follow-sunrise" "${label} follow sunrise" "mdi:weather-sunset-up")
        (mkSwitch "follow-sunset" "${label} follow sunset" "mdi:weather-sunset-down")
        (mkSwitch "invert" "${label} sun-follow invert" "mdi:swap-vertical")
      ]
      ++ lib.optional (!isSwitch) (mkSwitch "allow-wake" "${label} sun-follow can turn on" "mdi:power");

      numbers =
        if isSwitch then
          [
            (mkNumber "threshold" "${label} sun threshold" "mdi:brightness-6" {
              min = 0;
              max = 100;
              step = 5;
            })
          ]
        else
          [
            (mkNumber "min-brightness" "${label} min brightness" "mdi:brightness-4" {
              min = 0;
              max = 100;
              step = 5;
            })
            (mkNumber "max-brightness" "${label} max brightness" "mdi:brightness-7" {
              min = 0;
              max = 100;
              step = 5;
            })
            (mkNumber "gamma" "${label} brightness curve" "mdi:chart-bell-curve" {
              min = 0.3;
              max = 3.0;
              step = 0.1;
              unit = "";
            })
          ];

      buttons = [
        (mkButton "reset" "${label} sun-follow reset" "mdi:restart")
      ];
    in
    {
      service = mkAutomation {
        name = "sun-follow-${device}";
        bin = "sun-follow";
        description = "Sun-following ${mode} for ${device}";
        inherit env;
      };
      inherit switches numbers buttons;
    };

  sunFollowDevices = [
    {
      device = "light_1";
      mode = "brightness";
      label = "Living room light";
      publishDaylightSensor = true;
    }
    {
      device = "light_3";
      mode = "brightness";
      label = "Bedroom light";
      # sunrise-lights already owns the fixed-clock wake-up ramp; leave the
      # morning to it by default. Flip on in HA if ever wanted.
      defaultFollowSunrise = false;
    }
    {
      device = "plug_1";
      mode = "switch";
      label = "Plug 1";
    }
    {
      device = "plug_2";
      mode = "switch";
      label = "Plug 2";
    }
    {
      device = "plug_3";
      mode = "switch";
      label = "Plug 3";
    }
  ];

  sunFollowResults = map mkSunFollow sunFollowDevices;
  sunFollowServices = lib.mergeAttrsList (map (r: r.service) sunFollowResults);
  sunFollowSwitches = lib.concatMap (r: r.switches) sunFollowResults;
  sunFollowNumbers = lib.concatMap (r: r.numbers) sunFollowResults;
  sunFollowButtons = lib.concatMap (r: r.buttons) sunFollowResults;

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

  allServices = lib.mergeAttrsList (map mkAutomation automations) // sunFollowServices;
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
    ]
    ++ sunFollowNumbers;

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
    ]
    ++ sunFollowSwitches;

    mqtt.sensor = [
      {
        unique_id = "sun_follow_daylight_pct";
        name = "Daylight percentage";
        state_topic = daylightSensorTopic;
        value_template = "{{ value_json.daylight_pct }}";
        unit_of_measurement = "%";
        icon = "mdi:sun-clock";
      }
    ];

    mqtt.button = sunFollowButtons;
  };
}
