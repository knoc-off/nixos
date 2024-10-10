{ lib, config, inputs, pkgs, ... }:
with lib;
let
  # Define the available bootloader types
  bootloaderTypes = [ "grub" "systemd-boot" "lanzaboote" ];
in {
  imports = [ inputs.lanzaboote.nixosModules.lanzaboote ];
  options = {
    bootloader = {
      # Define an option to select the bootloader type
      type = mkOption {
        type = types.enum bootloaderTypes;
        default = "systemd-boot";
        description = "Select the bootloader type.";
      };

      # Define an option to enable or disable EFI support
      efiSupport = mkOption {
        type = types.bool;
        default = true;
        description = "Enable or disable EFI support.";
      };

      # Define an option to set the GRUB device for non-EFI systems
      grubDevice = mkOption {
        type = types.str;
        default = "";
        description = "The device to install GRUB on for non-EFI systems.";
      };
    };
  };

  config = mkMerge [
    # Import lanzaboote module if selected as bootloader type
    # Common bootloader and secure boot configuration
    {
      boot = {
        initrd.systemd.dbus.enable = true;

        lanzaboote.pkiBundle = "/etc/secureboot";

        loader = {
          efi.canTouchEfiVariables = config.bootloader.efiSupport;
          #boot.loader.efi.efiSysMountPoint = "/boot/efi";

          grub.enable = config.bootloader.type == "grub";
          grub.efiSupport = config.bootloader.efiSupport;
          #boot.loader.grub.device = if config.bootloader.efiSupport then "nodev" else config.bootloader.grubDevice;
          #boot.loader.grub.useOSProber = true; # Detect other operating systems

          systemd-boot.enable = config.bootloader.type == "systemd-boot";
          systemd-boot.editor =
            true; # Allow editing of boot entries at boot time
        };

        lanzaboote.enable = config.bootloader.type == "lanzaboote";
      };
    }
  ];
}
