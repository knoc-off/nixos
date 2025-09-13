{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.logiops;
  
  configFile = if cfg.configFile != null then cfg.configFile else pkgs.writeText "logid.cfg" cfg.config;

in
{
  options.services.logiops = {
    enable = mkEnableOption "logiops, Logitech Options on Linux";

    package = mkPackageOption pkgs "logiops" { };

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
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    services.udev.extraRules = ''
      # Ensure hidraw and uinput devices have proper permissions
      KERNEL=="hidraw*", SUBSYSTEM=="hidraw", GROUP="input", MODE="0660"
      KERNEL=="uinput", SUBSYSTEM=="misc", GROUP="uinput", MODE="0660"
      # Reload logiops when Logitech devices are added/removed
      ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="046d", TAG+="systemd", ENV{SYSTEMD_USER_WANTS}="logiops.service"
    '';

    systemd.services.logiops = {
      description = "Logiops daemon for Logitech devices";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-udev-settle.service" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${getExe cfg.package} --config ${configFile}";
        Restart = "always";
        RestartSec = "5s";
        StartLimitBurst = 5;
        StartLimitIntervalSec = 30;
      };
    };
  };
}