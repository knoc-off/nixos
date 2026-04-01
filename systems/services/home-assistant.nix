{
  config,
  lib,
  pkgs,
  ...
}: let
  slzb06Ip = "slzb-06";
in {
  imports = [
    ./mqtt-automations
  ];

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        port = 1883;

        settings = {
          allow_anonymous = true;
        };

        acl = [
          "topic readwrite #"
        ];
      }
    ];
  };

  services.zigbee2mqtt = {
    enable = true;
    settings = {
      homeassistant.enabled = true;
      mqtt = {
        base_topic = "zigbee2mqtt";
        server = "mqtt://localhost:1883";
      };

      frontend = {
        enabled = true;
        port = 7768;
        host = "0.0.0.0";
      };

      serial = {
        port = "tcp://${slzb06Ip}:6638";
        adapter = "zstack";
      };
    };
  };

  services.home-assistant = {
    enable = true;

    extraComponents = [
      "default_config"
      "met"
      "mqtt"
    ];

    config = {
      default_config = {};

      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
      };

      homeassistant = {
        name = "Home";
        unit_system = "metric";
      };

      # MQTT is configured via HA UI integration, not here.
      # Declarative mqtt config conflicts with the UI-based setup.

      notify = [
        {
          name = "all_phones";
          platform = "group";
          services = [
            {service = "mobile_app_pixel_10";}
            {service = "mobile_app_pixel_7";}
          ];
        }
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [
    8123 # Home Assistant
    7768 # Zigbee2MQTT
  ];

  # Z2M v4 auto-discovers .ts files in <dataDir>/external_converters/
  systemd.tmpfiles.rules = [
    "d /var/lib/zigbee2mqtt/external_converters 0755 zigbee2mqtt zigbee2mqtt -"
    "L+ /var/lib/zigbee2mqtt/external_converters/LTA016.ts - - - - ${./zigbee-converters/LTA016.ts}"
  ];

  systemd.services.mosquitto = {
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "2s";
    };
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 100;
    };
  };

  systemd.services.zigbee2mqtt = {
    after = ["mosquitto.service" "network-online.target"];
    wants = ["network-online.target"];
    bindsTo = ["mosquitto.service"];
    environment.NODE_OPTIONS = "--max-old-space-size=64";
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5s";
      MemoryMax = "120M";
      MemoryHigh = "100M";
    };
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 100;
    };
  };

  systemd.services.home-assistant = {
    after = ["mosquitto.service" "network-online.target"];
    wants = ["mosquitto.service" "network-online.target"];
    bindsTo = ["mosquitto.service"];
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5s";
      MemoryMax = "150M";
      MemoryHigh = "120M";
    };
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 100;
    };
  };
}
