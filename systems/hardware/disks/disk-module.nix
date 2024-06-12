{ lib, config, pkgs, ... }:

with lib;

let
  cfg = config.diskoCustom;
in
{
  options.diskoCustom = {
    bootType = mkOption {
      type = types.enum [ "bios" "efi" ];
      default = "bios";
      description = ''Type of boot partition. Can be "bios" or "efi".'';
    };

    swapSize = mkOption {
      type = types.str;
      default = "10G";
      description = ''Size of the swap partition.'';
    };

    diskDevice = mkOption {
      type = types.str;
      default = "/dev/vdb";
      description = ''The disk device to configure.'';
    };

    useSystemdBoot = mkOption {
      type = types.bool;
      default = false;
      description = ''Whether to use systemd-boot instead of GRUB.'';
    };
  };

  config = {
    assertions = [
      {
        assertion = !(cfg.bootType == "bios" && cfg.useSystemdBoot);
        message = "systemd-boot requires EFI support. Please set bootType to 'efi' or disable useSystemdBoot.";
      }
    ];

    disko.devices = {
      disk = {
        vdb = {
          device = mkDefault cfg.diskDevice;
          type = "disk";
          content = {
            type = "gpt";
            partitions = let
              bootPartition = if cfg.bootType == "bios" then {
                size = "1M";
                type = "EF02"; # for grub MBR
                priority = 1; # Needs to be the first partition
              } else {
                size = "512M";
                type = "EF00"; # for EFI
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                };
                priority = 1; # Needs to be the first partition
              };
            in {
              boot = bootPartition;
              root = {
                end = "-${cfg.swapSize}";
                content = {
                  type = "filesystem";
                  format = "ext4";
                  mountpoint = "/";
                };
              };
              swap = {
                size = "100%";
                content = {
                  type = "swap";
                  resumeDevice = true; # resume from hibernation from this device
                };
              };
            };
          };
        };
      };
    };

    # GRUB configuration
    boot.loader.grub = mkIf (!cfg.useSystemdBoot) {
      enable = true;
      device = if cfg.bootType == "efi" then "nodev" else "";
      efiSupport = cfg.bootType == "efi";
      efiInstallAsRemovable = cfg.bootType == "efi";
    };

    # systemd-boot configuration
    boot.loader.systemd-boot = mkIf cfg.useSystemdBoot {
      enable = true;
    };
    boot.loader.efi.canTouchEfiVariables = mkIf cfg.useSystemdBoot true;
  };
}
