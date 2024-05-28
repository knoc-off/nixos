{
  modulesPath,
  inputs,
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [

    # Sops
    #inputs.sops-nix.nixosModules.sops
    #{
    #  sops.defaultSopsFile = ./secrets/hetzner/default.yaml;
    #  # This will automatically import SSH keys as age keys
    #  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    #  sops.secrets = if config.services.nextcloud.enable then {
    #    "services/nextcloud/admin-pass" = {
    #      owner = config.users.users.nextcloud.name;
    #    };
    #  } else {};
    #}


    # nix package settings
    ./modules/nix.nix


    # boot
    ./hardware/boot.nix

    # message at boot.
    #./commit-message.nix

    # services
    #./services/nginx.nix

    # nextcloud
    # ./services/nextcloud.nix
    # ./services/wordpress.nix
    # ./services/wordpress-oci.nix
  ];


  bootloader = {
    type = "grub"; # Set the desired bootloader type
    efiSupport = false; # Disable EFI support
    grubDevice = "/dev/sda"; # Set the correct GRUB device
  };

  networking.hostName = "nserver";
  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [80 443];
    allowedUDPPorts = [80 443];
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

  # Use the systemd-boot EFI boot loader.
  # disable if using lanzaboote
  #boot.loader.systemd-boot.enable = true;
  #boot.loader.efi.canTouchEfiVariables = true;




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
