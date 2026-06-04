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
    pluginName = "confined-floats";
    version = "1.0-unstable";

    src = pkgs.fetchFromGitHub {
      owner = "mennemann";
      repo = "hyprland-confined-floats";
      rev = "a2f9ec247c2a4db5319769faee474c605746ea7a";
      hash = "sha256-C1KOIhwGSjP0NZDfsEzYtHUE3Yj7BHd5T4R/ZtyC7/4=";
    };

    nativeBuildInputs = with pkgs; [cmake];

    meta = {
      homepage = "https://github.com/mennemann/hyprland-confined-floats";
      description = "Prevent floating windows from moving off-screen";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  })
