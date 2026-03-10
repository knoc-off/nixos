{
  lib,
  config,
  inputs,
  ...
}:
with lib; let
  cfg = config.disks.btrfsLuks;

  subvolumeType = types.submodule {
    options = {
      mountpoint = mkOption {
        type = types.str;
        description = "Where to mount this subvolume.";
      };
      mountOptions = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
        description = "Mount options for this subvolume. Set to null to use the module defaults (compression + mountOptions).";
      };
    };
  };

  defaultMountOptions = subvolOpts:
    if subvolOpts.mountOptions != null
    then subvolOpts.mountOptions
    else
      (optional (cfg.compression != "none") "compress=${cfg.compression}")
      ++ cfg.mountOptions;

  defaultSubvolumes = {
    "/root" = {mountpoint = "/"; mountOptions = null;};
    "/home" = {mountpoint = "/home"; mountOptions = null;};
    "/nix" = {mountpoint = "/nix"; mountOptions = null;};
  };

  allSubvolumes = defaultSubvolumes // cfg.extraSubvolumes;

  buildSubvolumes = let
    regular =
      mapAttrs (_name: subvol: {
        mountpoint = subvol.mountpoint;
        mountOptions = defaultMountOptions subvol;
      })
      allSubvolumes;

    swap = optionalAttrs (cfg.swapSize != null) {
      "/swap" = {
        mountpoint = "/.swapvol";
        mountOptions = ["noatime"];
        swap.swapfile.size = cfg.swapSize;
      };
    };
  in
    regular // swap;
in {
  imports = [
    inputs.disko.nixosModules.disko
  ];

  options.disks.btrfsLuks = {
    enable = mkEnableOption "BTRFS on LUKS encrypted disk layout";

    device = mkOption {
      type = types.str;
      default = "/dev/nvme0n1";
      description = "The disk device to partition.";
    };

    diskName = mkOption {
      type = types.str;
      default = "primary";
      description = "Internal disko disk identifier name.";
    };

    luksName = mkOption {
      type = types.str;
      default = "crypted";
      description = "Name for the LUKS encrypted volume.";
    };

    espSize = mkOption {
      type = types.str;
      default = "512M";
      description = "Size of the EFI System Partition.";
    };

    swapSize = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "32G";
      description = "Size of the btrfs swapfile. Set to null to disable swap.";
    };

    allowDiscards = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to allow TRIM/discard on the LUKS volume. Enable for SSDs.";
    };

    compression = mkOption {
      type = types.enum ["zstd" "lzo" "zlib" "none"];
      default = "zstd";
      description = "Btrfs compression algorithm.";
    };

    mountOptions = mkOption {
      type = types.listOf types.str;
      default = ["noatime"];
      description = "Base mount options applied to all subvolumes (in addition to compression).";
    };

    luksPasswordFile = mkOption {
      type = types.nullOr types.str;
      default = "/tmp/secret.key";
      description = ''
        Path on the target machine where the LUKS passphrase file is located during install.
        Used by nixos-anywhere with --disk-encryption-keys to provide the passphrase.
        After install, the file is gone and the system prompts interactively on boot.
        Set to null to always prompt interactively (won't work with nixos-anywhere).
      '';
    };

    hibernation = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable hibernation support. Sets boot.resumeDevice to the LUKS volume.
        Requires swap to be enabled (swapSize != null) and systemd initrd
        (boot.initrd.systemd.enable = true) for automatic resume_offset detection
        via EFI variables (systemd 255+).
      '';
    };

    extraSubvolumes = mkOption {
      type = types.attrsOf subvolumeType;
      default = {};
      example = literalExpression ''
        {
          "/var/log" = {
            mountpoint = "/var/log";
          };
          "/.snapshots" = {
            mountpoint = "/.snapshots";
            mountOptions = [ "noatime" ];
          };
        }
      '';
      description = ''
        Additional btrfs subvolumes beyond the defaults (/root, /home, /nix).
        Each subvolume inherits the module's compression and mountOptions unless overridden.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.hibernation -> cfg.swapSize != null;
        message = "disks.btrfsLuks: hibernation requires swap. Set swapSize to enable swap.";
      }
    ];

    boot.resumeDevice = mkIf cfg.hibernation "/dev/mapper/${cfg.luksName}";

    disko.devices.disk.${cfg.diskName} = {
      type = "disk";
      device = cfg.device;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = cfg.espSize;
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = ["defaults"];
            };
          };
          luks = {
            size = "100%";
            content = {
              type = "luks";
              name = cfg.luksName;
              passwordFile = cfg.luksPasswordFile;
              settings = {
                allowDiscards = cfg.allowDiscards;
              };
              content = {
                type = "btrfs";
                extraArgs = ["-f"];
                subvolumes = buildSubvolumes;
              };
            };
          };
        };
      };
    };
  };
}
