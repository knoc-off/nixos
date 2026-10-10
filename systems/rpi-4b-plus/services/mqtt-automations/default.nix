# MQTT automations other than lighting (that is services/lighting): Rust
# binaries from pkgs/mqtt-automations, configured through the environment.
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  inherit (import ../../devices.nix) devices;

  mqttPkg = self.packages.${pkgs.stdenv.hostPlatform.system}.mqtt-automations;
in
{
  systemd.services.mqtt-auto-cat-doorbell = {
    description = "Notify phone on motion detection (cat doorbell)";
    after = [
      "mosquitto.service"
      "network-online.target"
    ];
    wants = [
      "mosquitto.service"
      "network-online.target"
    ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      SENSOR_TOPIC = "zigbee2mqtt/${devices.kitchen.motion.name}";
      NTFY_URL = "https://ntfy.niko.ink";
      NTFY_TOPIC = "cat-doorbell";
      COOLDOWN_SECONDS = "300";
      NOTIFICATION_TITLE = "Cat Doorbell";
      NTFY_TOKEN_FILE = config.sops.secrets."services/ntfy/publish-token".path;
      CURL_BIN = "${pkgs.curl}/bin/curl";
    };
    serviceConfig = {
      ExecStart = lib.getExe' mqttPkg "cat-doorbell";
      Restart = "always";
      RestartSec = "10s";
    };
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 20;
    };
  };
}
