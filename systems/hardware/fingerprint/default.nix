{ inputs, lib, ... }:
{
  services.fprintd = {
    enable = true;
    tod = {
      enable = true;
      driver = inputs.fprint.lib.libfprint-2-tod1-vfs0090-bingch {
        calib-data-file = ./calib-data.bin;
      };
    };
  };

#  security.pam.services.swaylock.text = ''
#    auth sufficient pam_fprintd.so
#${pkgs.fprintd}/lib/security/pam_fprintd.so
#    '';
  # "${pkgs.fprintd}/lib/security/pam_fprintd.so"
}
