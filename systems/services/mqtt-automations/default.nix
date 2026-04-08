# MQTT automations -- Rust binaries from pkgs/mqtt-automations.
# Config via environment variables; buttons get a generated JSON file.
{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  mqttPkg = self.packages.${pkgs.stdenv.hostPlatform.system}.mqtt-automations;

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
        NOTIFY_SERVICE = "notify.all_phones";
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
      };
    }
    {
      name = "button-dispatcher";
      bin = "button-dispatcher";
      description = "Button action dispatcher";
      args = ["${buttonConfig}"];
    }
  ];

  allServices = lib.foldl' (acc: def: acc // (mkAutomation def)) {} automations;
in {
  systemd.services = allServices;
}
