{
  lib,
  config,
  inputs,
  ...
}:
with lib; let
  cfg = config.boot.custom;
in {
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  options.boot.custom = {
    enable = mkEnableOption "custom bootloader configuration";

    type = mkOption {
      type = types.enum ["grub" "systemd-boot" "lanzaboote"];
      default = "systemd-boot";
      description = "The bootloader type to use.";
    };

    efiSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable EFI support.";
    };

    grubDevice = mkOption {
      type = types.str;
      default = "";
      description = "The device to install GRUB on for non-EFI systems.";
    };

    pkiBundle = mkOption {
      type = types.str;
      default = "/etc/secureboot";
      description = "Path to the lanzaboote PKI bundle for secure boot.";
    };

    editor = mkOption {
      type = types.bool;
      default = false;
      description = "Allow editing boot entries at boot time (systemd-boot). Disable for security.";
    };

    initrdSystemdDbus = mkOption {
      type = types.bool;
      default = true;
      description = "Enable systemd dbus in initrd.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.type == "lanzaboote" -> cfg.efiSupport;
        message = "Lanzaboote (secure boot) requires EFI support. Set boot.custom.efiSupport = true.";
      }
      {
        assertion = (cfg.type == "grub" && !cfg.efiSupport) -> (cfg.grubDevice != "");
        message = "GRUB without EFI requires a grubDevice to be set. Set boot.custom.grubDevice.";
      }
    ];

    boot = {
      initrd.systemd.dbus.enable = cfg.initrdSystemdDbus;

      loader = {
        efi.canTouchEfiVariables = cfg.efiSupport;

        systemd-boot = mkIf (cfg.type == "systemd-boot") {
          enable = true;
          editor = cfg.editor;
        };

        grub = mkIf (cfg.type == "grub") {
          enable = true;
          efiSupport = cfg.efiSupport;
          device =
            if cfg.efiSupport
            then "nodev"
            else cfg.grubDevice;
        };
      };

      lanzaboote = mkIf (cfg.type == "lanzaboote") {
        enable = true;
        pkiBundle = cfg.pkiBundle;
      };
    };
  };
}
