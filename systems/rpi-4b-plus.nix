{
  self,
  lib,
  config,
  inputs,
  pkgs,
  ...
}: {
  imports = [
    self.nixosModules.nix
    {
      # Pi runs a Nix version that lacks the wasm-builtin feature
      nix.settings.experimental-features = lib.mkForce ["nix-command" "flakes" "pipe-operators"];
    }
    inputs.sops-nix.nixosModules.sops

    ./services/home-assistant.nix
    ./services/caddy-lan.nix
    ./services/tailscale.nix
  ];

  sops = {
    defaultSopsFile = ./secrets/rpi-4b-plus/default.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets."wifi/home/fritz" = {};
    secrets."ntfy/token" = {};
  };

  # Without this the running system falls back to UTC (the Europe/Berlin
  # setting in sdImage.nix only applies to the image build, not the switched
  # system) — making journald/logs read 2h behind local time.
  time.timeZone = "Europe/Berlin";

  boot = {
    kernelPackages = pkgs.linuxPackages_rpi4;
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
    blacklistedKernelModules = ["btsdio" "hci_uart" "bluetooth"]; # fails every boot
  };

  hardware = {
    enableRedistributableFirmware = true;
    bluetooth.enable = false;
  };

  # gpu_mem=16 set manually in /dev/mmcblk0p1/config.txt -- must re-apply after re-flash

  # in-RAM compressed swap, faster than SD card
  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
    priority = 100;
  };

  # systemd-oomd unavailable (no PSI support on this kernel)
  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = false;
  };

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  networking = {
    hostName = "rpi-4b-plus";
    wireless = {
      enable = true;
      secretsFile = config.sops.secrets."wifi/home/fritz".path;
      networks."FRITZ!Box 7590 SI".pskRaw = "ext:PSK0";
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [22 443 8123];
      allowedUDPPorts = [];
    };
  };

  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 1024;
    }
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.libraspberrypi
  ];

  users.users = {
    root = {
      initialPassword = "password";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
      ];
    };
  };

  system.stateVersion = "25.11";
}
