{
  self,
  lib,
  config,
  inputs,
  pkgs,
  hostname,
  ...
}: {
  imports = [
    self.nixosModules.nix
    {
      nix.settings.experimental-features = lib.mkForce ["nix-command" "flakes" "pipe-operators"];
    }
    inputs.sops-nix.nixosModules.sops
    inputs.hardware.nixosModules.raspberry-pi-4

    ./services/home-assistant.nix
    ./services/caddy-lan.nix
    self.nixosModules.tailnet
    {services.tailnet.enable = true;}
  ];

  sops = {
    defaultSopsFile = ./secrets/${hostname}/default.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets."wifi/home/fritz" = {};
    secrets."ntfy/token" = {};
  };

  time.timeZone = "Europe/Berlin";

  boot = {
    # Use the mainline aarch64 kernel: it is prebuilt on cache.nixos.org, whereas
    # the Raspberry Pi vendor kernel (linux-rpi) is cached nowhere and rebuilds
    # from source (~1h+) on every nixpkgs bump. nixos-hardware's raspberry-pi-4
    # module selects the vendor kernel via mkDefault, so force mainline here.
    kernelPackages = lib.mkForce pkgs.linuxPackages;
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
    # WiFi dropped for now: the Pi is on wired ethernet (end0). Dual-homing both
    # interfaces on the same /24 caused an IP conflict (FritzBox handed .54 to both
    # MACs via the hostname reservation) and asymmetric routing that made .54
    # unreachable. Keep the block + PSK secret so WiFi can be re-enabled by flipping
    # enable back to true.
    wireless = {
      enable = false;
      secretsFile = config.sops.secrets."wifi/home/fritz".path;
      networks."FRITZ!Box 7590 SI".pskRaw = "ext:PSK0";
    };
    # Static IP on ethernet so end0 deterministically owns .54, matching
    # Home Assistant's internal_url (http://192.168.178.54:8123). Keep a matching
    # DHCP reservation on the FritzBox (MAC dc:a6:32:0e:56:34) so nothing else
    # is handed .54 dynamically.
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.178.54";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = "192.168.178.1";
    nameservers = ["192.168.178.1"];
    firewall = {
      enable = true;
      allowedTCPPorts = [22 443 8123];
      allowedUDPPorts = [];
    };
  };

  # The Broadcom WiFi (brcmfmac) defaults to power_save=on, which collapses
  # throughput to ~1 Mbit/s with huge latency despite an excellent link (-36 dBm,
  # 390 Mbit/s PHY). Disabling it restores ~25 Mbit/s. Bound to the device so it
  # re-applies on every wlan0 appearance (reboot or interface flap).
  systemd.services.wifi-powersave-off = {
    wantedBy = ["multi-user.target"];
    after = ["sys-subsystem-net-devices-wlan0.device"];
    bindsTo = ["sys-subsystem-net-devices-wlan0.device"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.iw}/bin/iw dev wlan0 set power_save off";
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
