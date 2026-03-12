# Declarative Windows 11 VM via NixVirt.
#
# Usage:
#   1. Place the Windows 11 ISO at /var/lib/libvirt/isos/windows11.iso
#      (or set windows-vm.isoPath to a custom location).
#      The path must be readable by the qemu user — avoid /home paths
#      when libvirtd runs QEMU as non-root.
#
#   2. Rebuild: sudo nixos-rebuild switch --flake .#<host>
#
#   3. (Optional) Set windows-vm.autounattendFile to an autounattend.xml
#      to automate installation (debloat, skip MS account, dark mode, etc.).
#      Example with the UnattendedWinstall flake input:
#        windows-vm.autounattendFile =
#          "${inputs.UnattendedWinstall}/autounattend.xml";
#      The file is built into a small ISO and attached as an extra CDROM.
#      Set to null after installation is complete.
#
#   4. Open virt-manager, start the "windows-vm" domain.
#
#   5. VirtIO drivers during installation:
#      If autounattendFile is set, VirtIO driver paths are automatically
#      injected into the answer file — Windows Setup loads storage and
#      network drivers without manual intervention. Skip to step 6.
#
#      If installing manually (no autounattend), the disk and network
#      won't be visible because Windows lacks VirtIO drivers. The VirtIO
#      driver ISO is already attached as a second CDROM (drive E:).
#
#      To load the storage driver (required to see the disk):
#        - Click "Load driver" > Browse
#        - Navigate to E:\viostor\w11\amd64
#        - Select the "Red Hat VirtIO SCSI controller" driver
#        - The 100 GB disk will then appear for installation
#
#      To load the network driver (required for internet):
#        - Click "Load driver" > Browse
#        - Navigate to E:\NetKVM\w11\amd64
#        - Select the "Red Hat VirtIO Ethernet Adapter" driver
#
#   6. After installation, open File Explorer > E: drive and run
#      virtio-win-guest-tools.exe — this single installer bundles all
#      VirtIO drivers (balloon, serial, display, SCSI, etc.) plus the
#      SPICE guest agent (clipboard sharing, auto-resolution).
#      No need to manually install individual drivers from step 5.
#
#   7. Enable SSH access from the host (inside the Windows VM):
#      a. Open PowerShell as Administrator and run:
#           Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
#           Start-Service sshd
#           Set-Service -Name sshd -StartupType Automatic
#      b. Allow SSH through Windows Firewall:
#           New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
#      c. Find the VM's IP from the host:
#           sudo virsh net-dhcp-leases default
#         The VM has a static DHCP reservation at 192.168.122.129.
#
#   8. File transfer between host and VM (from the host terminal):
#        scp myfile.txt <user>@192.168.122.129:C:/Users/<user>/Desktop/
#        scp <user>@192.168.122.129:C:/Users/<user>/Documents/file.txt ./
#      To avoid typing the password each time: ssh-copy-id <user>@192.168.122.129
#
#   9. Reaching host services from the VM:
#      The host is reachable at 192.168.122.1 from inside the VM.
#      For example, a service on host localhost:3000 is accessible at:
#        http://192.168.122.1:3000
#      The virtualization module opens the host firewall on virbr0 for this.
#      VM traffic goes through the host network stack, including VPNs.
#
#  10. Shared folder (virtiofs):
#      A host directory is shared with the VM via virtiofs (set via
#      windows-vm.sharePath, default /var/lib/libvirt/shared/windows-vm).
#      To access it inside Windows:
#        a. Install WinFSP: https://winfsp.dev/rel/ (or via winget:
#             winget install WinFsp.WinFsp
#           )
#        b. virtio-win-guest-tools (step 6) includes the VirtIO FS driver.
#        c. Start the VirtIO FS service (once, then it persists across reboots):
#             sc start VirtioFsSvc
#             sc config VirtioFsSvc start=auto
#        d. The shared folder appears as drive Z: in File Explorer.
#      Files placed in /var/lib/libvirt/shared/windows-vm on the host
#      are immediately visible inside the VM and vice versa.
#
#  11. Once done, set isoPath = null (and autounattendFile = null)
#      and rebuild to detach the installer ISOs from the VM definition.
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

  storagePath = cfg.storagePath;

  poolUUID = "4191d432-1897-4b2b-a02f-e41811f0298b";
  networkUUID = "3e9f8f79-67b8-4bd3-aeb9-3a50be2d610f";
  domainUUID = "8f1a52ac-750b-45ca-b939-0a456a178a78";

  # VirtIO driver path entries for the windowsPE pass of the answer file.
  # Windows Setup loads drivers from these paths during WinPE, so the VirtIO
  # disk and network are visible without manual "Load driver" steps.
  # We list multiple drive letters since the VirtIO ISO's letter is
  # unpredictable in WinPE; Windows silently ignores paths that don't exist.
  virtioDriverPathsXml = let
    letters = ["C" "D" "E" "F" "G" "H" "I" "J" "K"];
    driverDirs = ["viostor\\w11\\amd64" "NetKVM\\w11\\amd64" "Balloon\\w11\\amd64" "vioscsi\\w11\\amd64"];
    allPaths = lib.concatLists (map (l: map (d: {letter = l; dir = d;}) driverDirs) letters);
    pathEntries = lib.imap1 (i: p:
      ''        <PathAndCredentials wcm:action="add" wcm:keyValue="${toString i}"><Path>${p.letter}:\${p.dir}</Path></PathAndCredentials>''
    ) allPaths;
  in
    pkgs.writeText "virtio-driver-paths.xml" ''
      <component name="Microsoft-Windows-PnpCustomizationsWinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
        <DriverPaths>
  ${lib.concatStringsSep "\n" pathEntries}
        </DriverPaths>
      </component>
    '';

  # Build a minimal ISO containing autounattend.xml (patched with VirtIO
  # driver paths) for fully unattended install.
  autounattendIso =
    if cfg.autounattendFile != null
    then
      pkgs.runCommand "autounattend.iso" {
        nativeBuildInputs = with pkgs; [cdrtools gawk];
      } ''
        mkdir -p content
        # Inject VirtIO driver paths component into the windowsPE settings
        # pass of the answer file. The awk script inserts the XML right
        # before the first standalone </settings> (closing the windowsPE pass).
        awk '
          /^[[:space:]]*<\/settings>[[:space:]]*$/ && !done {
            while ((getline line < "${virtioDriverPathsXml}") > 0) print line;
            done=1
          }
          {print}
        ' ${cfg.autounattendFile} > content/autounattend.xml
        mkisofs -J -r -o $out content/
      ''
    else null;
in {
  imports = [inputs.NixVirt.nixosModules.default];

  options.windows-vm = {
    enable = lib.mkEnableOption "declarative Windows 11 VM via NixVirt";

    isoPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/var/lib/libvirt/isos/windows11.iso";
      description = ''
        Path to the Windows 11 ISO file (as a string, not a Nix path).
        Must be readable by the qemu user (avoid paths under /home
        when libvirtd runs qemu as non-root).
        Set to null after installation is complete to detach the installer ISO.
        The build succeeds even if this file doesn't exist yet —
        the VM just won't boot until the ISO is in place.
      '';
      example = "/var/lib/libvirt/isos/windows11.iso";
    };

    storagePath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/libvirt/images/windows-vm";
      description = "Directory to store the VM disk image and NVRAM.";
    };

    memoryGiB = lib.mkOption {
      type = lib.types.int;
      default = 15;
      description = "Amount of RAM allocated to the VM in GiB.";
    };

    diskSizeGB = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "Size of the VM disk in GB (thin-provisioned QCOW2).";
    };

    vcpus = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Number of virtual CPUs allocated to the VM.";
    };

    sharePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/var/lib/libvirt/shared/windows-vm";
      description = ''
        Host directory shared with the VM via virtiofs.
        Appears as a network drive in Windows after installing
        WinFSP and the VirtIO FS driver (both in virtio-win-guest-tools).
        Set to null to disable shared folder.
      '';
    };

    autounattendFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an autounattend.xml for automated Windows installation.
        A small ISO containing this file is built and attached as a CDROM;
        Windows setup reads it automatically from any mounted drive.
        Set to null after installation is complete (like isoPath).

        Example with the UnattendedWinstall flake input:
          windows-vm.autounattendFile =
            "''${inputs.UnattendedWinstall}/autounattend.xml";
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Virtualization base (inlined from virtualization-config)
    virtualisation.libvirtd = {
      enable = true;
      onBoot = "ignore";
      onShutdown = "shutdown";
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = false;
        swtpm.enable = true; # TPM emulation for Windows 11
      };
    };

    virtualisation.spiceUSBRedirection.enable = true;

    programs.virt-manager.enable = true;

    environment.systemPackages = with pkgs; [
      virt-viewer
      spice
      spice-gtk
      spice-protocol
      virtio-win
      win-spice
      virtiofsd
    ];

    users.users.${user}.extraGroups = ["libvirtd"];

    # Allow VMs on the NAT bridge to reach host services
    networking.firewall.interfaces."virbr0".allowedTCPPortRanges = [
      {from = 1; to = 65535;}
    ];

    # Fix: upstream service hardcodes /usr/bin/sh (NixOS #496836)
    systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart = let
      script = pkgs.writeShellScript "virt-secret-init-encryption" ''
        umask 0077 && (dd if=/dev/random status=none bs=32 count=1 | ${pkgs.systemd}/bin/systemd-creds encrypt --name=secrets-encryption-key - /var/lib/libvirt/secrets/secrets-encryption-key)
      '';
    in
      lib.mkForce ["" script];

    # Ensure the storage and shared directories exist
    systemd.tmpfiles.rules =
      [
        "d ${storagePath} 0755 root root -"
        "d /var/lib/libvirt/isos 0755 root root -"
        "d /var/lib/swtpm-localca 0750 tss tss -"
        "d /var/log/swtpm/libvirt/qemu 0750 tss tss -"
      ]
      ++ lib.optionals (cfg.sharePath != null) [
        "d ${cfg.sharePath} 0777 root root -"
      ];

    # NixVirt configuration
    virtualisation.libvirt = {
      enable = true;
      swtpm.enable = true; # Required for Windows 11 TPM 2.0
      verbose = false;

      connections."qemu:///system" = {
        # Storage pool for VM images
        pools = [
          {
            definition = nixvirt.lib.pool.writeXML {
              name = "windows-vm";
              uuid = poolUUID;
              type = "dir";
              target = {path = storagePath;};
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
                  target = {
                    format = {type = "qcow2";};
                  };
                };
              }
            ];
          }
        ];

        # NAT network bridge for the VM with static DHCP reservation
        networks = [
          {
            definition = nixvirt.lib.network.writeXML {
              name = "default";
              uuid = networkUUID;
              forward = {
                mode = "nat";
                nat = {
                  port = {
                    start = 1024;
                    end = 65535;
                  };
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

        # Windows 11 VM domain
        domains = let
          baseDomain = nixvirt.lib.domain.templates.windows {
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
            nvram_path = "${storagePath}/windows-vm.nvram";
            virtio_net = true;
            virtio_drive = true;
            virtio_video = true;
            install_virtio = true;
          };

          # Extra CDROM disks (autounattend answer file)
          extraDisks =
            lib.optionals (autounattendIso != null) [
              {
                type = "file";
                device = "cdrom";
                driver = {
                  name = "qemu";
                  type = "raw";
                };
                source = {file = "${autounattendIso}";};
                target = {
                  bus = "sata";
                  dev = "hde";
                };
                readonly = true;
              }
            ];

          # Extra device overrides (virtiofs, autounattend CDROM)
          extraDevices =
            (lib.optionalAttrs (cfg.sharePath != null) {
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
            })
            // (lib.optionalAttrs (extraDisks != []) {
              disk = baseDomain.devices.disk ++ extraDisks;
            });

          # Shared memory backing required by virtiofs
          extraTop =
            lib.optionalAttrs (cfg.sharePath != null) {
              memoryBacking = {
                source = {type = "memfd";};
                access = {mode = "shared";};
              };
            };

          finalDomain =
            baseDomain
            // extraTop
            // {
              devices = baseDomain.devices // extraDevices;
            };
        in [
          {
            definition = nixvirt.lib.domain.writeXML finalDomain;
            # Don't auto-start/stop — manage via virt-manager
            active = null;
          }
        ];
      };
    };
  };
}
