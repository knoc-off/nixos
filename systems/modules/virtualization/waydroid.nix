{ pkgs, ... }:
{
  virtualization.waydroid.enable = true;


  # oneshot service to init waydroid:
  systemd.services.waydroid-init = {
    description = "Waydroid init";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    script = ''
      #!/bin/bash
      ${pkgs.waydroid} init
    '';
  };

}

