{pkgs, ...}: {
  home.packages = with pkgs; [
    lutris
  ];

  #home.sessionVariables = {
  #  LUTRIS_SKIP_INIT = true;
  #};
}
