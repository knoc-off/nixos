{ config, lib, pkgs, ... }:
let
  users = [
    ./users/root.nix
    ./users/knoff.nix
    # Add other user files here
  ];
in {
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
  };

  users = lib.mkMerge users;
}
