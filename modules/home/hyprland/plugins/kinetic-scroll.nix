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

  kinetic-scroll = hyprlandPlugins.mkHyprlandPlugin (finalAttrs: {
    pluginName = "hypr-kinetic-scroll";
    version = "0.2.0-unstable";

    src = pkgs.fetchFromGitHub {
      owner = "savonovv";
      repo = "hypr-kinetic-scroll";
      rev = "1b6db350b05aa61fadf02d1454525b17a7e40ca6";
      hash = "sha256-pgePtnfgduPR4OLJ+iOFXu86R0qLr13LTQydRhoiKro=";
    };

    buildInputs = with pkgs; [
      pango
      cairo
      libinput
      udev
      wayland
      libxkbcommon
    ];

    dontUseCmakeConfigure = true;

    buildPhase = "make all";

    installPhase = ''
      mkdir -p $out/lib
      cp hypr-kinetic-scroll.so $out/lib/
    '';

    meta = {
      homepage = "https://github.com/savonovv/hypr-kinetic-scroll";
      description = "Compositor-level kinetic touchpad scrolling for Hyprland";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  });
in {
  wayland.windowManager.hyprland.plugins = [kinetic-scroll];
}
