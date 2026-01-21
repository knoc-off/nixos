{
  modulesPath,
  inputs,
  config,
  lib,
  pkgs,
  ...
}: let
  settingsFormat = pkgs.formats.yaml {};

  config = {
    config = {
      lite = {
        enabled = true;
        routes = [
          {
            host = "*.kobbl.co";
            backend = "localhost:25500";
          }
          {
            host = ["kobbl.co" "localhost"];
            backend = ["localhost:25500"];
          }
        ];
      };
    };
  };

  configFile = settingsFormat.generate "config.yaml" config;
in {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")

    # Disko
    inputs.disko.nixosModules.disko
    #./systems/hardware/disks/simple-disk.nix
    ./hardware/disks/disk-module.nix
    {
      diskoCustom = {
        bootType = "bios"; # Choose "bios" or "efi"
        swapSize = "12G"; # Size of the swap partition
        diskDevice = "/dev/sda"; # The disk device to configure
      };
      #disko.devices.disk.vdb.device = "/dev/disk/by-id/wwn-0x502b2a201d1c1b1a";
    }

    ./modules/nix.nix

    #inputs.sops-nix.nixosModules.sops {
    #  sops.defaultSopsFile = ./secrets/homeserver/default.yaml;
    #  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    #  sops.secrets."services/acme/namecheap-user" = {};
    #  sops.secrets."services/acme/namecheap-key" = {};
    #  sops.secrets."services/acme/namecheap-user-env" = {};
    #  sops.secrets."services/acme/namecheap-key-env" = {};
    #  sops.secrets."services/acme/envfile" = {};
    #}

    inputs.nix-minecraft.nixosModules.minecraft-servers

    #./services/traefik.nix
  ];

  nix.settings.auto-optimise-store = true;

  systemd.services.gateService = {
    description = "Gate Service";
    after = ["network.target" "minecraft-server-vanilla.service" "minecraft-server-vanilla2.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.gate}/bin/gate -c ${configFile}";
      Restart = "always";
      User = "root";
    };
  };

  nixpkgs.overlays = [inputs.nix-minecraft.overlay];
  nixpkgs.config.allowUnfree = true;
  services.minecraft-servers = {
    eula = true;
    enable = true;
    servers.beez = {
      jvmOpts = "-Xmx4G -Xms4G";
      enable = true;
      #package = pkgs.fabricServers.fabric-1_21.override { loaderVersion = "0.15.11"; };
      serverProperties = {
        server-port = 25500;
        difficulty = 3;
        motd = "The Beez";
        spawn-protection = 0;
        level-name = "world";
        level-seed = 2786386421968123439;

        # Rcon
        enable-rcon = true;
        "rcon.password" = "123";
        "rcon.port" = 25570;
      };
      symlinks = {
        "ops.json" = pkgs.writeTextFile {
          name = "ops.json";
          text = ''
            [
              {
                "uuid": "c9e17620-4cc1-4d83-a30a-ef320cc099e6",
                "name": "knoc_off",
                "level": 4,
                "bypassesplayerlimit": true
              },
              {
                "uuid": "c33fb94b-1e45-4bf2-b558-b363503c1e4e",
                "name": "DBMarshmallow22",
                "level": 4,
                "bypassesplayerlimit": true
              },
              {
                "uuid": "a09514fe-e2d6-42aa-98d8-243686e5b6f7",
                "name": "Oddfan11",
                "level": 4,
                "bypassesplayerlimit": true
              }
            ]
          '';
        };
        "server-icon.png" = ./server-icon.png;
      };
    };
    #servers.pre =
    #{
    #  enable = true;
    #  package = pkgs.fabricServers.fabric-1_21.override { loaderVersion = "0.15.11"; };
    #  #package = pkgs.vanillaServers.vanilla-1_21;
    #  symlinks = {
    #    "ops.json" = pkgs.writeTextFile {
    #      name = "ops.json";
    #      text = ''
    #        [
    #          {
    #            "uuid": "c9e17620-4cc1-4d83-a30a-ef320cc099e6",
    #            "name": "knoc_off",
    #            "level": 4,
    #            "bypassesplayerlimit": true
    #          },
    #          {
    #            "uuid": "c33fb94b-1e45-4bf2-b558-b363503c1e4e",
    #            "name": "DBMarshmallow22",
    #            "level": 4,
    #            "bypassesplayerlimit": true
    #          },
    #          {
    #            "uuid": "a09514fe-e2d6-42aa-98d8-243686e5b6f7",
    #            "name": "Oddfan11",
    #            "level": 4,
    #            "bypassesplayerlimit": true
    #          }

    #        ]
    #      '';
    #    };
    #    "server-icon.png" = ./server-icon.png;
    #  };
    #  serverProperties = {
    #    server-port = 25500;
    #    difficulty = 3;
    #    level-name = "world3";
    #    motd = "beez pre 1.21 this world will be wiped 2";
    #    "enable-rcon" = true;
    #    "rcon.password" = "123";
    #    "rcon.port" = 25575;

    #  };
    #};
  };

  services.logind = {
    extraConfig = ''
      HandleLidSwitch=ignore
      HandleLidSwitchDocked=ignore
    '';
  };

  #boot.loader.grub = {
  #  efiSupport = true;
  #  efiInstallAsRemovable = true;
  #};

  #boot.loader.systemd-boot.enable = true;
  #boot.loader = {
  #  efi = {
  #    canTouchEfiVariables = true;
  #  };
  #};

  networking = {
    hostName = "nserv";
    firewall = {
      enable = false;
      allowedUDPPorts = [22 80 443 25565];
      allowedTCPPorts = [22 80 443 25565];
    };
  };

  # static ip
  #  networking.interfaces."enp0s31f6" = {
  #    useDHCP = true;
  #    #ipv4.addresses = [
  #    #  {
  #    #    address = "192.168.1.102";
  #    #    prefixLength = 24;
  #    #  }
  #    #];
  #  };

  # Enable NetworkManager
  #networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  #networking.defaultGateway = "192.168.1.254"; # my router
  #networking.nameservers = [ "8.8.8.8" "8.8.4.4" ];

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "23.11";
}
