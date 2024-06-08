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
  };

  config = {
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
  };
}
