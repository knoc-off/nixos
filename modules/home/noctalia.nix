{
  inputs,
  lib,
  pkgs,
  ...
}: {
  imports = [inputs.noctalia.homeModules.default];
  home.packages = with pkgs; [
    hicolor-icon-theme
  ];

  programs.noctalia-shell = {
    enable = lib.mkDefault true;
    settings = lib.mkDefault {
      bar.position = "left";
    };
  };
}
