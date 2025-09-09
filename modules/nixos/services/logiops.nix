{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.logiops;
  
  deviceType = types.submodule {
    options = {
      name = mkOption {
        type = types.str;
        example = "MX Master 3S";
        description = "Device name as reported by the device";
      };

      buttons = mkOption {
        type = types.listOf buttonType;
        default = [];
        description = "Button configurations";
      };

      scroll = mkOption {
        type = types.nullOr scrollType;
        default = null;
        description = "Scroll wheel configuration";
      };
    };
  };

  buttonType = types.submodule {
    options = {
      cid = mkOption {
        type = types.str;
        example = "0xc3";
        description = "Control ID of the button (hex format)";
      };

      action = mkOption {
        type = actionType;
        description = "Action to perform when button is pressed";
      };
    };
  };

  actionType = types.submodule {
    options = {
      type = mkOption {
        type = types.enum [ "Keypress" "Gesture" "ToggleSmartShift" "ToggleHiresScroll" "CycleDPI" ];
        description = "Type of action";
      };

      keys = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        example = [ "KEY_LEFTCTRL" "KEY_C" ];
        description = "Keys to press (for Keypress action)";
      };
    };
  };

  scrollType = types.submodule {
    options = {
      hires = mkOption {
        type = types.bool;
        default = true;
        description = "Enable high-resolution scrolling";
      };

      invert = mkOption {
        type = types.bool;
        default = false;
        description = "Invert scroll direction";
      };

      target = mkOption {
        type = types.bool;
        default = false;
        description = "Enable scroll target";
      };
    };
  };

  formatButton = button: ''
    {
      cid: ${button.cid};
      action = {
        type: "${button.action.type}";
        ${optionalString (button.action.keys != null) ''keys: [${concatMapStringsSep ", " (key: ''"${key}"'') button.action.keys}];''}
      };
    }'';

  formatScroll = scroll: ''
    {
      hires: ${boolToString scroll.hires};
      invert: ${boolToString scroll.invert};
      target: ${boolToString scroll.target};
    }'';

  formatDevice = device: ''
    {
      name: "${device.name}";
      ${optionalString (device.buttons != []) ''buttons: (${concatMapStringsSep ",\n    " formatButton device.buttons});''}
      ${optionalString (device.scroll != null) ''scroll: (${formatScroll device.scroll});''}
    }'';

  configFile = pkgs.writeText "logid.cfg" ''
    devices: (
      ${concatMapStringsSep ",\n  " formatDevice cfg.devices}
    );
  '';

in
{
  options.services.logiops = {
    enable = mkEnableOption "logiops, Logitech Options on Linux";

    package = mkPackageOption pkgs "logiops" { };

    devices = mkOption {
      type = types.listOf deviceType;
      default = [];
      description = "Logitech devices to configure";
      example = [{
        name = "MX Master 3S";
        buttons = [{
          cid = "0xc3";
          action = {
            type = "Keypress";
            keys = [ "KEY_LEFTCTRL" "KEY_C" ];
          };
        }];
        scroll = {
          hires = true;
          invert = false;
          target = false;
        };
      }];
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    users.groups.logiops = {};
    users.users.logiops = {
      isSystemUser = true;
      group = "logiops";
      extraGroups = [ "input" "uinput" ];
    };

    services.udev.extraRules = ''
      # Allow logiops user to access hidraw and uinput devices
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
        User = "logiops";
        Group = "logiops";
        ExecStart = "${getExe cfg.package} --config ${configFile}";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}