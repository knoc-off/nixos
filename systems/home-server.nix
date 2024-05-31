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
    lite = {
      enabled = true;
      routes = [
        { host = "abc.kobbl.co"; backend = "localhost:25500"; }
        { host = "*.kobbl.co"; backend = "localhost:25501"; }
        { host = [ "kobbl.co" "localhost" ]; backend = [ "localhost:25500" ]; }
      ];
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
    servers.vanilla = {
      enable = true;
      #package = pkgs.fabricServers.fabric-1_20_2.override { loaderVersion = "0.15.11"; };
      package = pkgs.vanillaServers.vanilla-1_20_2;
      serverProperties = {
        server-port = 25500;
        difficulty = 3;
        motd = "NixOS Minecraft server 1";
      };
    };
    servers.vanilla2 = {
      enable = true;
      #package = pkgs.fabricServers.fabric-1_20_4.override { loaderVersion = "0.15.11"; };
      package = pkgs.vanillaServers.vanilla-1_20_2;
      serverProperties = {
        server-port = 25501;
        difficulty = 3;
        motd = "NixOS Minecraft server 2";
      };
    };
  };

  boot.loader.grub = {
    enable = true;
  };

  networking.hostName = "nserver";
  networking.firewall = {
    enable = false;
    allowedUDPPorts = [22 80 443];
    allowedTCPPorts = [22 80 443];
  };

  networking.interfaces."enp3s0" = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.1.100";
        prefixLength = 24;
      }
    ];
  };

  networking.defaultGateway = "192.168.1.254";
  networking.nameservers = [ "8.8.8.8" "8.8.4.4" ];

  services.openssh.enable = true;

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "23.11";
}
