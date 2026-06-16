{
  self,
  lib,
  inputs,
  pkgs,
  hostname,
  ...
}: let
  # Must match the server name defined in ./services/minecraft.nix.
  serverName = "bricks-building-extended";
in {
  imports = [
    self.nixosModules.nix

    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/${hostname}/default.yaml;
        age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
        secrets."services/minecraft/env" = {};
      };
    }

    self.nixosModules.tailnet
    {services.tailnet.enable = true;}

    # Plain BTRFS (no LUKS) so the box boots unattended for Wake-on-LAN
    # boot-on-demand. @minecraft is a dedicated subvolume at the nix-minecraft
    # dataDir for atomic, frequent world snapshots independent of the rootfs.
    self.nixosModules.btrfs-luks
    {
      disks.btrfsLuks = {
        enable = true;
        encryption = false;
        device = "/dev/nvme0n1";
        swapSize = "8G"; # OOM safety net only; the heap is sized to fit in RAM.
        extraSubvolumes."/minecraft".mountpoint = "/srv/minecraft";
      };
    }

    # Generic AMD hardware enablement from nixos-hardware (maintained upstream).
    # common-cpu-amd -> microcode updates; common-pc-ssd -> periodic fstrim.
    # No machine-specific hardware scan is needed: btrfs/disko owns fileSystems,
    # the flake sets hostPlatform, and boot.initrd.includeDefaultModules already
    # ships nvme/ahci/xhci/usbhid for a stock NVMe box.
    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-pc-ssd

    self.nixosModules.boot
    {
      boot.custom = {
        enable = true;
        # After first install: enroll secure boot keys with `sbctl`, then switch
        # to "lanzaboote".
        type = "systemd-boot";
        efiSupport = true;
      };
    }

    ./services/minecraft.nix
  ];

  time.timeZone = "Europe/Berlin";

  # AMD Ryzen + AMD GPU, headless. Microcode comes from common-cpu-amd (gated on
  # enableRedistributableFirmware, also needed for NIC firmware on the WOL path).
  hardware = {
    enableRedistributableFirmware = true;
    bluetooth.enable = false;
  };
  # Load amdgpu only to drive the console if a monitor is ever attached for
  # debugging. The full graphics stack (common-gpu-amd / mesa) is intentionally
  # omitted -- this server never renders. Add common-gpu-amd later if you want
  # VAAPI transcoding or a local display.
  boot.kernelModules = ["amdgpu"];

  # Wake-on-LAN: arm WoL ("g" = wake on MagicPacket) on every wired NIC as it
  # appears, independent of its kernel name (enp*/eno*). Requires Ethernet --
  # WoWLAN over WiFi is unreliable. Also enable "Power On By PCI-E" / "Wake on
  # LAN" in the BIOS and disable ErP/Deep Sleep, or S5 wake won't arm.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="en*", RUN+="${pkgs.ethtool}/bin/ethtool -s %k wol g"
  '';

  # Heap sized for the NeoForge modpack on this 16 GB box: an 8 GB heap leaves
  # ~8 GB for the OS and BTRFS page cache. Overrides the modpack's 6 GB default.
  services.minecraft-servers.servers.${serverName}.jvmOpts = lib.mkForce (
    lib.concatStringsSep " " [
      "-Xms4G"
      "-Xmx8G"
      "-XX:+UseG1GC"
      "-XX:+ParallelRefProcEnabled"
      "-XX:MaxGCPauseMillis=200"
      "-XX:+UnlockExperimentalVMOptions"
      "-XX:+DisableExplicitGC"
      "-XX:+AlwaysPreTouch"
    ]
  );

  networking.firewall = {
    enable = true;
    # Game + RCON are opened on tailscale0 by ./services/minecraft.nix, and
    # Tailscale opens its own UDP port. The WAN side exposes only SSH.
    allowedTCPPorts = [22];
    allowedUDPPorts = [];
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.ethtool
  ];

  users.users.root = {
    initialPassword = "password";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
    ];
  };

  system.stateVersion = "25.11";
}
