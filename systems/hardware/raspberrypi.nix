{ config, modulesPath, lib, pkgs, ... }:

{
  imports = [
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ];

  nixpkgs.config.allowUnsupportedSystem = true;
  nixpkgs.hostPlatform.system = "aarch64-linux";

  # Swap configuration
  swapDevices = [{
    device = "/var/lib/swapfile";
    size = 2 * 1024; # 2 GB
  }];

  # Boot loader configuration
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Networking
  networking.networkmanager.enable = true;

  # OpenSSH configuration
  services.openssh = {
    enable = true;
  };

  # Common system packages
  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    libraspberrypi
  ];

  # User configuration
  users.users.root = {
    initialPassword = "password";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
    ];
  };
}
