{ modulesPath, inputs, outputs, config, lib, pkgs, self, ... }: {
  imports = [
    # Sops
    # inputs.sops-nix.nixosModules.sops
    # {
    #   sops = {
    #     defaultSopsFile = ./secrets/hetzner/default.yaml;
    #     # This will automatically import SSH keys as age keys
    #     age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    #     secrets = if config.services.nextcloud.enable then {
    #       "services/nextcloud/admin-pass" = {
    #         owner = config.users.users.nextcloud.name;
    #       };
    #     } else
    #       { };
    #   };
    # }
    # Disko
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix

    # nix package settings
    ./modules/nix.nix

    # VPN Server
    # ./services/wireguard.nix

    # Syncthing
    # ./services/syncthing.nix # this should be enabled again, for media?

  ];
  nix.settings.auto-optimise-store = true;

  networking.hostName = "nux";
  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
  };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;

  environment.systemPackages = map lib.lowPrio [ pkgs.curl pkgs.gitMinimal ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "24.11";
}
