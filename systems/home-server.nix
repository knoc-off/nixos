{
  modulesPath,
  inputs,
  config,
  lib,
  pkgs,
  ...
}:

let
  settingsFormat = pkgs.formats.yaml {};

  config = {
    config = {
      lite = {
        enabled = true;
        routes = [
          {
            host = "abc.kobbl.co";
            backend = "localhost:25500";
          }
          {
            host = "*.kobbl.co";
            backend = "localhost:25501";
          }
          {
            host = [ "kobbl.co" "localhost" ];
            backend = [ "localhost:25500" ];
          }
        ];
      };
    };
  };

  configFile = settingsFormat.generate "config.yaml" config;

in

{
  imports = [
    ./modules/nix.nix

    inputs.sops-nix.nixosModules.sops {
      sops.defaultSopsFile = ./secrets/homeserver/default.yaml;
      sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
      sops.secrets."services/acme/namecheap-user" = {};
      sops.secrets."services/acme/namecheap-key" = {};
      sops.secrets."services/acme/namecheap-user-env" = {};
      sops.secrets."services/acme/namecheap-key-env" = {};
      sops.secrets."services/acme/envfile" = {};
    }

    inputs.nix-minecraft.nixosModules.minecraft-servers

    #./services/traefik.nix
  ];

  nix.settings.auto-optimise-store = true;

  systemd.services.gateService = {
    description = "Gate Service";
    after = [ "network.target" "minecraft-server-vanilla.service" "minecraft-server-vanilla2.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.gate}/bin/gate -c ${configFile}";
      Restart = "always";
      User = "root";
    };
  };

  nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];
  nixpkgs.config.allowUnfree = true;

  services.minecraft-servers = {
    eula = true;
    enable = true;
    servers.beez = {
      enable = true;
      #package = pkgs.fabricServers.fabric-1_20_4.override { loaderVersion = "0.15.11"; };
      package = pkgs.vanillaServers.vanilla-1_20_6;
      serverProperties = {
        server-port = 25500;
        difficulty = 3;
        motd = "Beez Server v0.1.0";
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
                "bypassesPlayerLimit": false
              }
            ]
          '';
        };
        "server-icon.png" = ./server-icon.png;
      };


    };
    servers.CCC =

    {
      enable = true;
      package = pkgs.fabricServers.fabric-1_20_1.override { loaderVersion = "0.15.11"; };
      #package = pkgs.vanillaServers.vanilla-1_20_2;
      serverProperties = {
        server-port = 25501;
        difficulty = 3;
        motd = "NixOS Minecraft server 2";
      };
    };
  };



  services.logind = {
    extraConfig = ''
      HandleLidSwitch=ignore
      HandleLidSwitchDocked=ignore
    '';
  };

  boot.loader.systemd-boot.enable = true;

  boot.loader = {
    efi = {
      canTouchEfiVariables = true;
    };
  };

  networking = {
    hostName = "nikoserver";
    firewall = {
      enable = true;
      allowedUDPPorts = [ 22 80 443 25565 ];
      allowedTCPPorts = [ 22 80 443 25565 ];
    };
  };

  # static ip
  networking.interfaces."enp0s31f6" = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.1.102";
        prefixLength = 24;
      }
    ];
  };

  networking.defaultGateway = "192.168.1.254"; # my router
  networking.nameservers = [ "8.8.8.8" "8.8.4.4" ];

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
