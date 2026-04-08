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
        host = "127.0.0.1"; # no auth on Z2M frontend
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
        use_x_forwarded_for = true; # Caddy proxies via WireGuard
        trusted_proxies = ["10.100.0.1"];
      };

      homeassistant = {
        name = "Home";
        unit_system = "metric";
        external_url = "https://home.niko.ink";
        internal_url = "http://192.168.178.54:8123";
      };

      # MQTT configured via HA UI -- declarative config conflicts with it

      notify = [
        {
          name = "all_phones";
          platform = "group";
          services = [
            {service = "mobile_app_pixel_10";}
            {service = "mobile_app_pixel_7a";}
            {service = "mobile_app_eileens_iphone";}
          ];
        }
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [8123];

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
    environment.NODE_OPTIONS = "--max-old-space-size=128";
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5s";
      MemoryMax = "256M";
      MemoryHigh = "200M";
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
      MemoryMax = "512M";
      MemoryHigh = "400M";
    };
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 100;
    };
  };
}
