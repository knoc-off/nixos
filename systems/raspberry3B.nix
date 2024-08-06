{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Sops
    #inputs.sops-nix.nixosModules.sops
    #{
    #  sops.defaultSopsFile = ./secrets/rpi3B/default.yaml;
    #  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

    #  sops.secrets."hashedpassword" = {};
    #  sops.secrets."wifi/envFile0" = {};
    #}

    # nix package settings
    ./modules/nix.nix

    # message at boot.
    ./commit-messages/raspberry3B-commit-message.nix

    ./services/octoprint.nix
  ];

  # static ip
  #networking.interfaces."wlan0" = {
  #  useDHCP = false;
  #  ipv4.addresses = [
  #    {
  #      address = "192.168.1.155";
  #      prefixLength = 24;
  #    }
  #  ];
  #};

  # swap:
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 2 * 1024; # 2 GB
    }
  ];

  # Networking
  networking.hostName = "rpi3B"; # Define your hostname.
  networking.networkmanager.enable = true;
  #networking.wireless.enable = true;

  # Firewall
  networking.firewall = {
    enable = false;
    #allowedTCPPorts = [ 22 80 443 ];
  };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
    #settings.KbdInteractiveAuthentication = false;
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.libraspberrypi
  ];

  users.users.root.initialPassword = "password";
  #users.users.root.hashedPasswordFile = config.sops.secrets."hashedpassword".path;

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKgy7SAvRGJPBcvt0WA/1oAoR4hDpmJBfRCGqWrygUKG root@nserver"
  ];

  system.stateVersion = "23.11";
}
