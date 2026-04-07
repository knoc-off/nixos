{
  lib,
  config,
  inputs,
  hostname,
  pkgs,
  ...
}: {
  imports = [
    inputs.sops-nix.nixosModules.sops

    ./services/home-assistant.nix
  ];

  sops = {
    defaultSopsFile = ./secrets/${hostname}/default.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets."wifi/home/fritz" = {};
    secrets."ha/api_token" = {};
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_rpi4;
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
    # Disable bluetooth (fails every boot, saves memory)
    blacklistedKernelModules = ["btsdio" "hci_uart" "bluetooth"];
  };

  hardware = {
    enableRedistributableFirmware = true;
    bluetooth.enable = false;
  };

  # NOTE: gpu_mem=16 is set manually in /dev/mmcblk0p1/config.txt (firmware partition)
  # This reduces GPU memory from 64MB to 16MB, freeing ~48MB for the system.
  # Must be re-applied if the SD card is re-flashed.

  # Compressed in-RAM swap - much faster than SD card swap, effectively
  # multiplies available memory via compression (~2-3x ratio)
  zramSwap = {
    enable = true;
    memoryPercent = 50; # up to 50% of RAM as zram swap
    algorithm = "zstd";
    priority = 100; # prefer zram over disk swap
  };

  # Userspace OOM killer - prevents hard lockups by killing the largest
  # process before the system becomes completely unresponsive.
  # systemd-oomd cannot work on this kernel (no PSI support).
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
    hostName = hostname;
    wireless = {
      enable = true;
      secretsFile = config.sops.secrets."wifi/home/fritz".path;
      networks."FRITZ!Box 7590 SI".pskRaw = "ext:PSK0";
    };
    firewall = {enable = false;};
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
