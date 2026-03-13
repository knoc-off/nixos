# Declarative Windows 11 VM via NixVirt.
#
# Usage:
#   1. Place the Windows 11 ISO at /var/lib/libvirt/isos/windows11.iso
#      (or set windows-vm.isoPath). Must be readable by the qemu user.
#
#   2. Rebuild: sudo nixos-rebuild switch --flake .#<host>
#
#   3. (Optional) Set autounattendFile to automate installation:
#        windows-vm.autounattendFile =
#          "${inputs.UnattendedWinstall}/autounattend.xml";
#      This debloats Windows, skips MS account, injects VirtIO drivers,
#      and runs post-install setup (guest tools, WinFSP, virtiofs)
#      automatically. Set to null after install is complete.
#
#   4. Start the VM in virt-manager.
#
#   5. VirtIO drivers: with autounattendFile set, drivers load
#      automatically during WinPE. Without it, manually load from
#      the VirtIO CDROM: E:\viostor\w11\amd64 (storage) and
#      E:\NetKVM\w11\amd64 (network).
#
#   6. Post-install: with autounattendFile, virtio-win-guest-tools,
#      WinFSP and VirtioFsSvc are set up at first login automatically.
#      Check C:\ProgramData\vm-setup.log for status.
#      Without it: run virtio-win-guest-tools.exe from the VirtIO drive.
#
#   7. SSH: inside the VM run (PowerShell as Admin):
#        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
#        Start-Service sshd; Set-Service -Name sshd -StartupType Automatic
#      VM has a static DHCP reservation at 192.168.122.129.
#
#   8. Shared folder (virtiofs): host path set via sharePath option
#      (default /var/lib/libvirt/shared/windows-vm). Appears as Z:
#      in Windows after WinFSP + VirtioFsSvc are running.
#
#   9. Host is reachable from VM at 192.168.122.1 (virbr0 firewall opened).
#
#  10. Set isoPath/autounattendFile to null and rebuild when done.
{
  config,
  lib,
  pkgs,
  inputs,
  user,
  ...
}: let
  cfg = config.windows-vm;
  nixvirt = inputs.NixVirt;

  # Stable UUIDs for libvirt resources
  poolUUID = "4191d432-1897-4b2b-a02f-e41811f0298b";
  networkUUID = "3e9f8f79-67b8-4bd3-aeb9-3a50be2d610f";
  domainUUID = "8f1a52ac-750b-45ca-b939-0a456a178a78";

  # XML patcher as a proper Python derivation
  patchAutounattend = pkgs.writers.writePython3Bin "patch-autounattend" {
    flakeIgnore = ["E265" "E501"];
  } (
    builtins.readFile ./patch-autounattend.py
  );

  # Patched autounattend.xml with VirtIO driver paths + post-install commands
  patchedAutounattend =
    if cfg.autounattendFile != null
    then
      pkgs.runCommand "patched-autounattend.xml" {
        nativeBuildInputs = [patchAutounattend];
      } ''
        patch-autounattend \
          --input ${cfg.autounattendFile} \
          --output $out \
          --driver-dirs "viostor\w11\amd64,NetKVM\w11\amd64,Balloon\w11\amd64,vioscsi\w11\amd64" \
          --locale ${cfg.locale} \
          --username ${cfg.windowsUsername}
      ''
    else null;

  # Bundle VirtIO drivers + guest tools + patched XML + post-install script
  # into a single ISO.  This replaces NixVirt's separate virtio-win CDROM
  # so that virtio-win-guest-tools.exe, the driver tree, autounattend.xml,
  # and setup-vm.ps1 all live on the same drive letter — guaranteeing the
  # post-install script can always find the guest-tools installer.
  deployIso =
    if patchedAutounattend != null
    then
      pkgs.runCommand "deploy.iso" {
        nativeBuildInputs = [pkgs.cdrtools];
      } ''
        mkdir content
        cp -r ${pkgs.virtio-win}/* content/
        cp ${patchedAutounattend} content/autounattend.xml
        cp ${./setup-vm.ps1} content/setup-vm.ps1
        mkisofs -J -r -V DEPLOYISO -o $out content/
      ''
    else null;

  # Build the domain definition from the NixVirt windows template,
  # then layer on virtiofs and autounattend CDROM as needed.
  mkDomain = let
    base = nixvirt.lib.domain.templates.windows {
      name = "windows-vm";
      uuid = domainUUID;
      memory = {
        count = cfg.memoryGiB;
        unit = "GiB";
      };
      storage_vol = {
        pool = "windows-vm";
        volume = "windows-vm.qcow2";
      };
      install_vol =
        if cfg.isoPath != null
        then cfg.isoPath
        else null;
      nvram_path = "${cfg.storagePath}/windows-vm.nvram";
      virtio_net = true;
      virtio_drive = true;
      virtio_video = true;
      install_virtio = false;  # we bundle virtio-win into our deploy ISO
    };

    # virtiofs requires shared memory backing
    withVirtiofs =
      if cfg.sharePath != null
      then
        base
        // {
          memoryBacking = {
            source = {type = "memfd";};
            access = {mode = "shared";};
          };
          devices =
            base.devices
            // {
              filesystem = [
                {
                  type = "mount";
                  accessmode = "passthrough";
                  driver = {type = "virtiofs";};
                  binary = {path = "${pkgs.virtiofsd}/bin/virtiofsd";};
                  source = {dir = cfg.sharePath;};
                  target = {dir = "share";};
                }
              ];
            };
        }
      else base;

    # Attach the combined deploy ISO (virtio-win + autounattend + setup script)
    withDeployIso =
      if deployIso != null
      then
        withVirtiofs
        // {
          devices =
            withVirtiofs.devices
            // {
              disk =
                withVirtiofs.devices.disk
                ++ [
                  {
                    type = "file";
                    device = "cdrom";
                    driver = {
                      name = "qemu";
                      type = "raw";
                    };
                    source = {file = "${deployIso}";};
                    target = {
                      bus = "sata";
                      dev = "hdd";
                    };
                    readonly = true;
                  }
                ];
            };
        }
      else withVirtiofs;
  in
    withDeployIso;
in {
  imports = [inputs.NixVirt.nixosModules.default];

  options.windows-vm = {
    enable = lib.mkEnableOption "declarative Windows 11 VM via NixVirt";

    isoPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/var/lib/libvirt/isos/windows11.iso";
      description = ''
        Path to the Windows 11 ISO. Must be readable by the qemu user
        (avoid /home when libvirtd runs qemu as non-root).
        Set to null after installation to detach the installer ISO.
      '';
    };

    storagePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/libvirt/images/windows-vm";
      description = "Directory for the VM disk image and NVRAM.";
    };

    memoryGiB = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "RAM allocated to the VM in GiB.";
    };

    diskSizeGB = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "VM disk size in GB (thin-provisioned QCOW2).";
    };

    vcpus = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Virtual CPUs allocated to the VM.";
    };

    sharePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/var/lib/libvirt/shared/windows-vm";
      description = ''
        Host directory shared via virtiofs. Appears as Z: in Windows
        after WinFSP and VirtIO FS driver are installed.
        Set to null to disable.
      '';
    };

    locale = lib.mkOption {
      type = lib.types.str;
      default = "en-US";
      description = ''
        Windows locale for the installer UI and installed OS
        (input, system, UI, user locale). Examples: en-US, en-GB, nb-NO.
      '';
    };

    windowsUsername = lib.mkOption {
      type = lib.types.str;
      default = "user";
      description = ''
        Local administrator account created during unattended install.
        No password is set — the account auto-logs in once for
        FirstLogonCommands, then behaves as a normal local account.
      '';
    };

    autounattendFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = ./autounattend.xml;
      description = ''
        Answer file for automated Windows installation. The built-in
        default handles hardware bypasses, local account, VirtIO drivers,
        and post-install guest tools setup. Override with a custom XML
        (e.g. UnattendedWinstall) or set to null after installation
        to detach the ISO.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # --- Virtualization base ---
    virtualisation.libvirtd = {
      enable = true;
      onBoot = "ignore";
      onShutdown = "shutdown";
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = false;
        swtpm.enable = true;
      };
    };

    virtualisation.spiceUSBRedirection.enable = true;
    programs.virt-manager.enable = true;
    users.users.${user}.extraGroups = ["libvirtd"];

    environment.systemPackages = with pkgs; [
      virt-viewer
      spice
      spice-gtk
      spice-protocol
      virtio-win
      win-spice
      virtiofsd
    ];

    networking.firewall.interfaces."virbr0".allowedTCPPortRanges = [
      {
        from = 1;
        to = 65535;
      }
    ];

    # NixOS #496836: upstream service hardcodes /usr/bin/sh
    systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart = let
      script = pkgs.writeShellScript "virt-secret-init-encryption" ''
        umask 0077 && (dd if=/dev/random status=none bs=32 count=1 | ${pkgs.systemd}/bin/systemd-creds encrypt --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key)
      '';
    in
      lib.mkForce ["" script];

    # --- Directories ---
    systemd.tmpfiles.rules =
      [
        "d ${cfg.storagePath} 0755 root root -"
        "d /var/lib/libvirt/isos 0755 root root -"
        "d /var/lib/swtpm-localca 0750 tss tss -"
        "d /var/log/swtpm/libvirt/qemu 0750 tss tss -"
      ]
      ++ lib.optionals (cfg.sharePath != null) [
        "d ${cfg.sharePath} 0777 root root -"
      ];

    # --- NixVirt ---
    virtualisation.libvirt = {
      enable = true;
      swtpm.enable = true;
      verbose = false;

      connections."qemu:///system" = {
        pools = [
          {
            definition = nixvirt.lib.pool.writeXML {
              name = "windows-vm";
              uuid = poolUUID;
              type = "dir";
              target = {path = cfg.storagePath;};
            };
            active = true;
            volumes = [
              {
                definition = nixvirt.lib.volume.writeXML {
                  name = "windows-vm.qcow2";
                  capacity = {
                    count = cfg.diskSizeGB;
                    unit = "GB";
                  };
                  target.format = {type = "qcow2";};
                };
              }
            ];
          }
        ];

        networks = [
          {
            definition = nixvirt.lib.network.writeXML {
              name = "default";
              uuid = networkUUID;
              forward = {
                mode = "nat";
                nat.port = {
                  start = 1024;
                  end = 65535;
                };
              };
              bridge = {name = "virbr0";};
              ip = {
                address = "192.168.122.1";
                netmask = "255.255.255.0";
                dhcp = {
                  range = {
                    start = "192.168.122.2";
                    end = "192.168.122.254";
                  };
                  host = {
                    mac = "52:54:00:62:cc:b0";
                    name = "windows-vm";
                    ip = "192.168.122.129";
                  };
                };
              };
            };
            active = true;
          }
        ];

        domains = [
          {
            definition = nixvirt.lib.domain.writeXML mkDomain;
            active = null;
          }
        ];
      };
    };
  };
}
