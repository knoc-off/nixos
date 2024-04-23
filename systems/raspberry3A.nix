{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [

    # Sops
    inputs.sops-nix.nixosModules.sops
    {
      sops.defaultSopsFile = ./secrets/rpi3A/default.yaml;
      sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

      sops.secrets."hashedpassword" = {};
      sops.secrets."wifi/envFile0" = {};
    }

    # nix package settings
    ./modules/nix.nix

    # message at boot.
    ./commit-message.nix

    ./services/octoprint.nix

  ];

  # swap:
  swapDevices = [ {
    device = "/var/lib/swapfile";
    size = 2*1024; # 2 GB
  } ];


  # Networking
  networking.hostName = "rpi3A"; # Define your hostname.
  networking.networkmanager.enable = true;
  #networking.wireless.enable = true;

  #networking.wireless.environmentFile = config.sops.secrets."wifi/envFile0".path;
  #networking.wireless.networks = {
  #  Tiamat.psk = "@PSK0@";
  #};

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
    #settings.PasswordAuthentication = false;
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
  ];

  system.stateVersion = "23.11";
}

