{
  modulesPath,
  inputs,
  outputs,
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")

    # Sops
    inputs.sops-nix.nixosModules.sops
    {
      sops.defaultSopsFile = ./secrets/hetzner/default.yaml;
      # This will automatically import SSH keys as age keys
      sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

      sops.secrets =
        if config.services.nextcloud.enable
        then {
          "services/nextcloud/admin-pass" = {
            owner = config.users.users.nextcloud.name;
          };
        }
        else {};
    }

    # Disko
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix

    # nix package settings
    ./modules/nix.nix

    # services
    ./services/nginx.nix

    # mail
    ./services/imapfilter

    # Matrix
    #./services/matrix/dendrite.nix

    # Syncthing
    ./services/syncthing.nix

    # KitchenOwl
    ./services/kitchenowl.nix

    # nextcloud
    # ./services/nextcloud.nix
    # ./services/wordpress.nix
    # ./services/wordpress-oci.nix
  ];

  nixpkgs.overlays = builtins.attrValues outputs.overlays;
  nix.settings.auto-optimise-store = true;

  networking.hostName = "oink";
  # Firewall
  networking.firewall = {
    enable = false;
    allowedTCPPorts = [80 443];
    #allowedUDPPortRanges = [
    #  { from = 4000; to = 4007; }
    #  { from = 8000; to = 8010; }
    #];
  };

  # Not needed ?
  # This is using an age key that is expected to already be in the filesystem
  #sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  # This will generate a new key if the key specified above does not exist
  #sops.age.generateKey = true;
  # This is the actual specification of the secrets.
  #sops.secrets.example-key = {};
  #sops.secrets."myservice/my_subdir/my_secret" = {};

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
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
