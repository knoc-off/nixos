{ config, pkgs, lib, modulesPath, ... }:
let
  SSHKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  #setSSHKeys = name: userConfig:
  #  lib.mkIf (userConfig.isNormalUser or (name == "root")) {
  #    openssh.authorizedKeys.keys = lib.mkForce SSHKeys;
  #  };


in

{
  imports = [
    "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  config = {

    users.users.root.openssh.authorizedKeys.keys = lib.mkForce [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
    ];

    # Enable SSH for remote access
    services.openssh.enable = lib.mkForce true;
    services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

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

    disko.enableConfig = lib.mkForce false;

    # Optional: Set your preferred time zone
    time.timeZone = "Europe/Berlin";

    networking.networkmanager.enable = lib.mkForce false;
  };
    # why doesnt this work?
    # // (
    #   if (builtins.hasAttr "disko" config) then {
    #     disko.enableConfig = lib.mkForce false;
    # } else {}
    # );



}
