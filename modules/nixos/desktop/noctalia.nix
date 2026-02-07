{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [inputs.noctalia.nixosModules.default];

  services.noctalia-shell = {
    enable = lib.mkDefault true;
    package = lib.mkDefault (inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      calendarSupport = true;
    });
  };

  services.gnome.evolution-data-server.enable = lib.mkDefault true;
}
