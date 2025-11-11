{
  modulesPath,
  inputs,
  outputs,
  config,
  lib,
  pkgs,
  self,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")

    # Sops
    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/hetzner/default.yaml;
        # This will automatically import SSH keys as age keys
        age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

        secrets = {
          "services/website/env" = {
          };
          "services/kitchenowl/jwt-secret" = {
          };
          # "services/syncthing/gui-password" = {
          #   owner = "syncthing";
          #   group = "syncthing";
          #   mode = "0400";
          # };
        };

        #  if config.services.nextcloud.enable then {
        #  "services/nextcloud/admin-pass" = {
        #    owner = config.users.users.nextcloud.name;
        #  };
        #}  else
        #  { };
      };
    }
    # Disko
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix

    # nix package settings
    #./modules/nix.nix

    # services
    ./services/nginx.nix
    # ./services/website.nix

    # VPN
    #./services/wireguard.nix

    # ./services/imapfilter

    # Matrix
    #./services/matrix/dendrite.nix

    # ./services/syncthing-server.nix
    ./services/webdav.nix

    # KitchenOwl
    ./services/kitchenowl.nix
  ];

  # trilium notes:
  # override the trilium package to pull from a different source

  #nixpkgs.overlays = [
  #  (final: prev: {
  #    trilium-server = self.packages.${pkgs.system}.triliumNext;
  #  })
  #] ++ builtins.attrValues outputs.overlays;

  # services.trilium-server.enable = true;
  # services.trilium-server.port = 4223;
  # services.trilium-server.nginx.enable = true;
  # services.trilium-server.nginx.hostName = "trilium.niko.ink";

  # services.nginx = {
  #   # need to find a way to easily configure to domain name, not hard code it
  #   virtualHosts."trilium.niko.ink" = {
  #     forceSSL = true;
  #     enableACME = true;
  #     locations."/" = {
  #       proxyPass = "http://127.0.0.1:8080";
  #       proxyWebsockets = true; # Enable WebSocket support if needed

  #       extraConfig = ''
  #         proxy_set_header Upgrade $http_upgrade;
  #         proxy_set_header Connection "upgrade";
  #       '';
  #     };
  #   };
  # };

  #nixpkgs.overlays = ;

  # runs every build, slows down builds.
  nix.settings.auto-optimise-store = true;
  # runs as a service, i believe.
  nix.optimise.automatic = true;

  networking.hostName = "oink";
  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [80 443];
  };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;

  environment.systemPackages = map lib.lowPrio [pkgs.curl pkgs.gitMinimal];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "23.11";
}
