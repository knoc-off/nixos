{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  # Enable SSH for remote access
  services.openssh.enable = lib.mkDefault true;
  services.openssh.settings.PermitRootLogin = lib.mkDefault "yes";


  boot = {
    kernelPackages = lib.mkForce pkgs.linuxPackages;
    initrd.systemd.dbus.enable = true;
    loader = {
      systemd-boot.enable = if config.boot.lanzaboote.enable then lib.mkForce false else true;
      efi.canTouchEfiVariables = true;
    };
  };


  # Add any additional packages you want in the live environment
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    htop
  ];

  # Optional: Set your preferred time zone
  time.timeZone = "Europe/Berlin";

  networking.networkmanager.enable = lib.mkForce false;

  #networking.wireless = false;

  # Disable auto-login for better security in a live environment
  #services.getty.autologinUser = lib.mkForce null;
}
