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
    inputs.sops-nix.nixosModules.sops

    # ./services/caddy-lan.nix # makes sense for minecraft server?
    self.nixosModules.tailnet
    {services.tailnet.enable = true;}

    inputs.disko.nixosModules.disko
    {disko.devices.disk.vdb.device = "/dev/nvme0n1";}

    self.nixosModules.boot
    {
      boot.custom = {
        enable = true;
        # After first install: enroll secure boot keys with `sbctl`, then switch to "lanzaboote"
        # type = "lanzaboote";
        type = "systemd-boot";
        efiSupport = true;
      };
    }
  ];

  sops = {
    defaultSopsFile = ./secrets/${hostname}/default.yaml;
    age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    secrets."wifi/home/fritz" = {};
  };

  time.timeZone = "Europe/Berlin";

  hardware = {
    enableRedistributableFirmware = true;
    bluetooth.enable = false;
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
    priority = 100;
  };

  services.earlyoom = {
    enable = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 10;
    enableNotifications = false;
  };

  networking = {
    wireless = {
      enable = false;
      secretsFile = config.sops.secrets."wifi/home/fritz".path;
      networks."FRITZ!Box 7590 SI".pskRaw = "ext:PSK0";
    };
    firewall = {
      enable = true;
      allowedTCPPorts = [22 443 8123];
      allowedUDPPorts = [];
    };
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
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
