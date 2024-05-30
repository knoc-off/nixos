{
  modulesPath,
  inputs,
  config,
  lib,
  pkgs,
  ...
}: {
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

    ./services/traefik.nix
  ];

  nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];
  nixpkgs.config.allowUnfree = true;

  services.minecraft-servers = {
    eula = true;
    enable = true;
    servers.vanilla-fabric = {
      enable = true;
      package = pkgs.fabricServers.fabric-1_20_2.override { loaderVersion = "0.15.11"; };
      serverProperties = {
        server-port = 25500;
        difficulty = 3;
        motd = "NixOS Minecraft server 1";
      };
    };
    servers.vani-fabric = {
      enable = true;
      package = pkgs.fabricServers.fabric-1_20_4.override { loaderVersion = "0.15.11"; };
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
