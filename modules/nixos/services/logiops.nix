{
  lib,
  config,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.logiops;

  configFile =
    if cfg.configFile != null
    then cfg.configFile
    else pkgs.writeText "logid.cfg" cfg.config;
in {
  options.services.logiops = {
    enable = mkEnableOption "logiops, Logitech Options on Linux";

    package = mkPackageOption pkgs "logiops" {};

    config = mkOption {
      type = types.lines;
      default = "";
      description = "Raw logiops configuration";
      example = ''
        io_timeout: 60000.0;

        devices:
        (
          {
            name: "MX Master 3S";
            buttons:
            (
              {
                cid: 0x52;
                action:
                {
                  type: "Keypress";
                  keys: ["KEY_F13"];
                };
              }
            );
          }
        );
      '';
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to logiops configuration file (overrides config option)";
    };

    vendorId = mkOption {
      type = types.str;
      default = "046d";
      description = "USB vendor ID to trigger logiops on (default: 046d for Logitech)";
    };

    productIds = mkOption {
      type = types.listOf types.str;
      default = ["b034"];
      description = ''
        Optional list of USB product IDs to filter specific devices.
        If empty, triggers on any device matching vendorId.
      '';
      example = [
        "b034"
        "c52b"
      ];
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    services.udev.extraRules = let
      productIdMatch = optionalString (
        cfg.productIds != []
      ) '', ATTRS{idProduct}=="${concatStringsSep "|" cfg.productIds}"'';
    in ''
      # Ensure hidraw and uinput devices have proper permissions
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", GROUP="input", MODE="0660"
      KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="uinput", MODE="0660"

      # Start logiops when matching HID device connects (USB or Bluetooth)
      ACTION=="add", SUBSYSTEM=="hid", ATTRS{idVendor}=="${cfg.vendorId}"${productIdMatch}, TAG+="systemd", ENV{SYSTEMD_WANTS}+="logiops.service"
      ACTION=="bind", SUBSYSTEM=="hid", ATTRS{idVendor}=="${cfg.vendorId}"${productIdMatch}, DRIVER=="logitech-hidpp-device", TAG+="systemd", ENV{SYSTEMD_WANTS}+="logiops.service"

      # Stop logiops when matching HID device disconnects
      ACTION=="remove", SUBSYSTEM=="hid", ATTRS{idVendor}=="${cfg.vendorId}"${productIdMatch}, RUN+="${pkgs.systemd}/bin/systemctl stop logiops.service"
    '';

    systemd.services.logiops = {
      description = "Logiops daemon for Logitech devices";
      after = ["systemd-udev-settle.service"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${getExe cfg.package} --config ${configFile}";
        Restart = "on-failure";
        RestartSec = "5s";
        StartLimitBurst = 5;
      };
    };
  };
}
