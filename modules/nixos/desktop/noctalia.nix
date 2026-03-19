{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [inputs.noctalia.nixosModules.default];

  # The upstream systemd service is deprecated (delayed startup, unreliable IPC).
  # Noctalia is launched via `uwsm app` from the compositor's exec-once instead.
  services.noctalia-shell = {
    enable = lib.mkDefault false;
    package = lib.mkForce (inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      calendarSupport = true;
    });
  };

  services.gnome.evolution-data-server.enable = lib.mkDefault true;
}
