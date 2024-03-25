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
    inputs.sops-nix.nixosModules.sops

    # Disko, would be cool to have disko. ill try it out once i get a base img working
    # inputs.disko.nixosModules.disko
    # ./hardware/disks/simple-disk.nix

    # nix package settings
    ./modules/nix.nix

    # message at boot.
    ./commit-message.nix

  ];

  # Networking
  networking.hostName = "rpi3A"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.
  # Firewall
  networking.firewall = {
    enable = false;
    allowedTCPPorts = [ 22 80 443 ];
  };

  sops.defaultSopsFile = ./secrets/rpi3A/default.yaml;
  # This will automatically import SSH keys as age keys
  # so if i understand correctly sops will fail if the key doesent work
  # but i also cant get the key until the machine is booted,
  # so i need to find a way to bootstrap this step, so that i guess i can skip it
  # and then when the machine is booted, i can setup the sops file, and then load it back in
  # not sure if i like that, not very smooth. can look into it more.
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

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

  services.openssh = {
    enable = true;
    #settings.PasswordAuthentication = false;
    #settings.KbdInteractiveAuthentication = false;
  };

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
  ];

  # TODO: Replace with hashed password, why not
  users.users.root.initialPassword = "password";
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "23.11";
}

