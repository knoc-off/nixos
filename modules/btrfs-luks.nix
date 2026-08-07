{ inputs, ... }: {
  nixos = {
    lib,
    config,
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

      btrfsContent = {
        type = "btrfs";
        extraArgs = ["-f"];
        subvolumes = buildSubvolumes;
      };

      # The full-disk partition holding the btrfs filesystem. When encryption is
      # on it is a LUKS container wrapping btrfs; when off, btrfs sits directly
      # on the partition (required for unattended boot -- no passphrase prompt).
      rootPartition = {
        size = "100%";
        content =
          if cfg.encryption
          then {
            type = "luks";
            name = cfg.luksName;
            passwordFile = cfg.luksPasswordFile;
            # disko merges `settings` verbatim into boot.initrd.luks.devices.<name>.
            settings =
              {
                allowDiscards = cfg.allowDiscards;
              }
              // optionalAttrs cfg.tpm2Unlock {
                crypttabExtraOpts = ["tpm2-device=auto"];
              };
            content = btrfsContent;
          }
          else btrfsContent;
      };
    in {
      imports = [
        inputs.disko.nixosModules.disko
      ];

      options.disks.btrfsLuks = {
        enable = mkEnableOption "BTRFS on LUKS encrypted disk layout";

        encryption = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to encrypt the BTRFS volume with LUKS. Disable for headless
            hosts that must boot unattended (e.g. Wake-on-LAN boot-on-demand),
            where an interactive passphrase prompt at every boot is unacceptable.
            With encryption off, btrfs is created directly on the partition and
            the luks* / passwordFile options are ignored.
          '';
        };

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

        tpm2Unlock = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Unlock the LUKS volume from a TPM2-sealed keyslot in the systemd
            initrd, falling back to the passphrase prompt when the TPM policy
            does not match.

            Enrollment is deliberately not declarative -- the sealed key lives
            in the LUKS2 header, not in the Nix store. Run systemd-cryptenroll
            once on the installed system *before* turning this on, or the
            volume will simply prompt for the passphrase as usual.

            Only meaningful when the boot chain is measured: sealing against
            raw PCRs breaks on every kernel update, and PCR 7 alone does not
            cover the kernel or initrd. Prefer binding to a systemd-pcrlock
            policy generated by lanzaboote's measuredBoot (covers PCR 4, which
            with the lanzaboote stub covers the whole post-firmware chain).
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
          {
            assertion = cfg.hibernation -> cfg.encryption;
            message = "disks.btrfsLuks: hibernation resume is only wired for the encrypted layout (resumeDevice points at the LUKS mapper). Set encryption = true or disable hibernation.";
          }
          {
            assertion = cfg.tpm2Unlock -> cfg.encryption;
            message = "disks.btrfsLuks: tpm2Unlock requires an encrypted layout. Set encryption = true or disable tpm2Unlock.";
          }
          {
            assertion = cfg.tpm2Unlock -> config.boot.initrd.systemd.enable;
            message = "disks.btrfsLuks: tpm2Unlock needs systemd stage 1 -- crypttabExtraOpts is ignored by the scripted initrd. Set boot.initrd.systemd.enable = true (boot.custom.initrdSystemd does this).";
          }
        ];

        # tpm_crb covers Intel PTT / fTPM, tpm_tis covers discrete TPM chips.
        # Neither is in nixpkgs' default initrd module set, and without them
        # systemd-cryptsetup silently falls through to the passphrase prompt.
        boot.initrd.availableKernelModules = mkIf cfg.tpm2Unlock ["tpm_crb" "tpm_tis"];

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
            }
            // (
              if cfg.encryption
              then {luks = rootPartition;}
              else {root = rootPartition;}
            );
          };
        };
      };
    };
}
