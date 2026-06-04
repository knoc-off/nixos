{
  inputs,
  pkgs,
  lib,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
  hyprlandPlugins = pkgs.hyprlandPlugins.override {
    hyprland = inputs.hyprnix.packages.${system}.hyprland;
  };
in
  hyprlandPlugins.mkHyprlandPlugin (finalAttrs: {
    pluginName = "scrolloverview";
    version = "0.1-unstable";

    src = pkgs.fetchFromGitHub {
      owner = "yayuuu";
      repo = "hyprland-scroll-overview";
      rev = "716f6bcc";
      hash = "sha256-F3Jf47XuRWtXPeesImFnlJG5uiKdOcAYJNqQw6Uljlc=";
    };

    nativeBuildInputs = with pkgs; [cmake];

    buildInputs = with pkgs; [pango cairo lua5_4];

    meta = {
      homepage = "https://github.com/yayuuu/hyprland-scroll-overview";
      description = "Scrollable overview plugin for Hyprland";
      license = lib.licenses.bsd3;
      platforms = lib.platforms.linux;
    };
  })
