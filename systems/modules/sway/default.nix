{ lib, pkgs, ... }:
{
  imports = [
    #./sway.nix
    #./greetd.nix
  ];
  programs.light.enable = true;
  security.polkit.enable = true;

  # swaylock
  security.pam.services.swaylock = { };

  # preformace
  security.pam.loginLimits = [
    { domain = "@users"; item = "rtprio"; type = "-"; value = 1; }
  ];

  # kanshi systemd service
  systemd.user.services.kanshi = {
    description = "kanshi daemon";
    serviceConfig = {
      Type = "simple";
      ExecStart = ''${pkgs.kanshi}/bin/kanshi -c kanshi_config_file'';
    };
  };
}
