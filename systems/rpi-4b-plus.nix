{
  self,
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
    ./services/caddy-lan.nix

    ./services/wireguard.nix
    {
      # Home LAN clients cannot reach 10.100.0.1 without running WG
      # themselves. Point every lanServices hostname at the Pi's own
      # LAN IP so WiFi clients hit the Pi's Caddy directly. Caddy
      # serves home.niko.ink locally and transparent-proxies the rest
      # back to the hub over WG, where the proxied request arrives
      # from 10.100.0.2 and is trusted (auth skipped). The list of
      # rewritten subdomains defaults to attrNames lanServices, so no
      # explicit override is needed here.
      services.wireguard-network.dns = {
        enable = true;
        upstream = ["192.168.178.1"];
        lanOnlyAnswer = "192.168.178.54";
      };
    }

    self.nixosModules.services.cert-receiver
    {
      # Receive home.niko.ink cert from the hub's cert-sync. The
      # dispatch script accepts either an rsync drop (enforced by
      # rrsync -wo) or a reload-caddy keyword.
      services.cert-receiver = {
        enable = true;
        path = "/var/lib/caddy-certs";
        owner = "caddy";
        group = "caddy";
        reloadUnit = "caddy.service";
        reloadCommandName = "reload-caddy";
        authorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE1r+skHBEYfZS4mnZ/hAGFYho+SwqKuy3TUP/0hgUIj cert-sync@hetzner";
      };
    }
  ];

  sops = {
    defaultSopsFile = ./secrets/${hostname}/default.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets."wifi/home/fritz" = {};
    secrets."ha/api_token" = {};
    secrets."wireguard/private-key" = {};
  };

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
    hostName = hostname;
    wireless = {
      enable = true;
      secretsFile = config.sops.secrets."wifi/home/fritz".path;
      networks."FRITZ!Box 7590 SI".pskRaw = "ext:PSK0";
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [22 53 443 8123];
      allowedUDPPorts = [53];
    };

    wireguard.interfaces.wg0 = {
      ips = ["10.100.0.2/24"];
      privateKeyFile = config.sops.secrets."wireguard/private-key".path;
      peers = [
        {
          publicKey = "xhsyVKOlzOHtOSDsXU7d/CRdyzamNgotO8NocNLpFno=";
          endpoint = "157.90.17.55:51820";
          allowedIPs = ["10.100.0.0/24"];
          persistentKeepalive = 25;
        }
      ];
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
