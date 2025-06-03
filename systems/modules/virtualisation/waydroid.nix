{...}: {
  virtualisation.waydroid.enable = false;

  # oneshot service to init waydroid:
  #systemd.services.waydroid-init = {
  #  description = "Waydroid init";
  #  wantedBy = [ "waydroid-container.service" ];
  #  after = [ "waydroid-container.service" ];
  #  script = ''
  #    #!/bin/bash
  #    ${pkgs.waydroid} init
  #  '';
  #};
}
