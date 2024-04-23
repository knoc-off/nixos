{
  ...
}: {
  services.fprintd = {
    enable = true;
  };

  #security.pam.services.swaylock.text = ''
  #  auth sufficient pam_fprintd.so
  #  ${pkgs.fprintd}/lib/security/pam_fprintd.so
  #'';
  #"${pkgs.fprintd}/lib/security/pam_fprintd.so"
}
