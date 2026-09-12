{
  config,
  lib,
  pkgs,
  ...
}:
let
  slzb06Ip = "slzb-06";
in
{
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
        host = "127.0.0.1";
      };

      serial = {
        port = "tcp://${slzb06Ip}:6638";
        adapter = "zstack";
      };

      # Declared here (not groups.yaml) so it survives rebuilds; z2m only
      # writes back to `devices`, never to `groups`. No Zigbee-level bind yet
      # (button-dispatcher handles button_1 in software) -- binding button_1
      # to this group would let it keep working with the Pi off.
      groups."1" = {
        friendly_name = "living_room";
        devices = [
          "light_1"
          "plug_1"
          "plug_2"
          "plug_3"
        ];
      };
    };
  };

  services.home-assistant = {
    enable = true;

    customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
      apexcharts-card
    ];

    extraComponents = [
      "default_config"
      "met"
      "mqtt"
    ];

    config = {
      default_config = { };

      # Load custom card JS globally — no manual resource registration needed.
      frontend.extra_module_url = [
        "/local/nixos-lovelace-modules/apexcharts-card.js"
      ];

      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
        use_x_forwarded_for = true;
        # 10.100.0.1: Hetzner Caddy via WG (remote + VPN path).
        # 127.0.0.1: Pi-local Caddy on same host (home LAN path).
        trusted_proxies = [
          "10.100.0.1"
          "127.0.0.1"
        ];
      };

      homeassistant = {
        name = "Home";
        unit_system = "metric";
        external_url = "https://home.niko.ink";
        internal_url = "http://192.168.178.54:8123";
      };

      # MQTT configured via HA UI -- declarative config conflicts with it

      # cat-doorbell notifies via ntfy directly (NTFY_TOKEN_FILE), bypassing
      # HA's notify/mobile_app entirely.
    };
  };

  # z2m frontend: localhost-only, reverse-proxied by Caddy with auth_token
  # (see caddy-lan.nix). ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN overrides
  # settings.frontend.auth_token at runtime, keeping it out of /nix/store.
  # The secret itself is a bare token; the template adds the VAR= prefix
  # z2m expects in an EnvironmentFile.
  sops.secrets."zigbee2mqtt/frontend-auth-token" = { };
  sops.templates."z2m.env".content = ''
    ZIGBEE2MQTT_CONFIG_FRONTEND_AUTH_TOKEN=${config.sops.placeholder."zigbee2mqtt/frontend-auth-token"}
  '';

  networking.firewall.allowedTCPPorts = [
    8123
  ];

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
    after = [
      "mosquitto.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    bindsTo = [ "mosquitto.service" ];
    environment.NODE_OPTIONS = "--max-old-space-size=128";
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce "5s";
      MemoryMax = "256M";
      MemoryHigh = "200M";
      EnvironmentFile = config.sops.templates."z2m.env".path;
    };
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 100;
    };
  };

  systemd.services.home-assistant = {
    after = [
      "mosquitto.service"
      "network-online.target"
    ];
    wants = [
      "mosquitto.service"
      "network-online.target"
    ];
    bindsTo = [ "mosquitto.service" ];
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
