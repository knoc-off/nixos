{ lib, self, pkgs, ...}:
let

  # https://github.com/matt1432/nixos-configs/blob/805c3949459382ef2672d58b8b658137bac995af/devices/wim/modules/security.nix#L8
  inherit (lib) mkDefault mkBefore;
  inherit (self.packages.${pkgs.system}) grosshack;

  pam_fprintd_grosshackSo = "${grosshack}/lib/security/pam_fprintd_grosshack.so";

  # https://wiki.archlinux.org/title/Fprint#Login_configuration
  grosshackConfig = ''
    # pam-fprint-grosshack
    auth  sufficient  ${pam_fprintd_grosshackSo} timeout=99
    auth  sufficient  pam_unix.so try_first_pass nullok
  '';


in
{
  services.fprintd = {
    enable = true;
  };

  # https://stackoverflow.com/a/47041843
  security.pam.services = {
    sudo.text = mkDefault (mkBefore grosshackConfig);
    login.text = mkDefault (mkBefore grosshackConfig);
    polkit-1.text = mkDefault (mkBefore grosshackConfig);
    ags.text = mkDefault (mkBefore grosshackConfig);
    swaylock.text = mkDefault (mkBefore grosshackConfig);
  };


  #security.pam.services.swaylock.text = ''
  #  auth sufficient pam_fprintd.so
  #  ${pkgs.fprintd}/lib/security/pam_fprintd.so
  #'';
  #"${pkgs.fprintd}/lib/security/pam_fprintd.so"
}
