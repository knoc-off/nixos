{ lib, config, inputs, ... }:

with lib;

let
  # Define the available bootloader types
  bootloaderTypes = [ "grub" "systemd-boot" "lanzaboote" ];
in
{
  imports = [
    inputs.lanzaboote.nixosModules.lanzaboote
  ];
  options = {
    # Define an option to select the bootloader type
    bootloader.type = mkOption {
      type = types.enum bootloaderTypes;
      default = "systemd-boot";
      description = "Select the bootloader type.";
    };

    # Define an option to enable or disable EFI support
    bootloader.efiSupport = mkOption {
      type = types.bool;
      default = true;
      description = "Enable or disable EFI support.";
    };

    # Define an option to set the GRUB device for non-EFI systems
    bootloader.grubDevice = mkOption {
      type = types.str;
      default = "/dev/sda";
      description = "The device to install GRUB on for non-EFI systems.";
    };
  };

  config = mkMerge [
    # Import lanzaboote module if selected as bootloader type
    # Common bootloader and secure boot configuration
    {
      boot.lanzaboote.pkiBundle = "/etc/secureboot";

      boot.loader.efi.canTouchEfiVariables = config.bootloader.efiSupport;
      #boot.loader.efi.efiSysMountPoint = "/boot/efi";

      boot.loader.grub.enable = (config.bootloader.type == "grub");
      boot.loader.grub.efiSupport = config.bootloader.efiSupport;
      boot.loader.grub.device = if config.bootloader.efiSupport then "nodev" else config.bootloader.grubDevice;
      #boot.loader.grub.useOSProber = true; # Detect other operating systems

      boot.loader.systemd-boot.enable = (config.bootloader.type == "systemd-boot");
      boot.loader.systemd-boot.editor = true; # Allow editing of boot entries at boot time

      boot.lanzaboote.enable = (config.bootloader.type == "lanzaboote");
    }
  ];
}
