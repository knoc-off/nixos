{
  config,
  pkgs,
  ...
}: let
  slzb06Ip = "192.168.178.32";
in {
  imports = [
    # ./home-automations/dnd.nix
    ./home-automations/bedroom.nix
    ./home-automations/motion-doorbell.nix
  ];

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        address = "127.0.0.1";
        port = 1883;

        # Allow local anonymous clients (Z2M + HA)
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
    };
  };

  networking.firewall.allowedTCPPorts = [
    8123 # Home Assistant
    7768 # Zigbee2MQTT frontend
  ];
}
