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
      rev = "9fcc50d2eed77b5b70dd59c81968012ac57b6785";
      hash = "sha256-M4WoDRz8VzpS1+akcwWywyA8XYM6gzGSOx/BZRrSfLg=";
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
      cp hypr-kinetic-scroll.so $out/lib/libhypr-kinetic-scroll.so
    '';

    meta = {
      homepage = "https://github.com/savonovv/hypr-kinetic-scroll";
      description = "Compositor-level kinetic touchpad scrolling for Hyprland";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  });
in {
  wayland.windowManager.hyprland = {
    plugins = [kinetic-scroll];

    settings."plugin:kinetic-scroll" = {
      enabled = 1;
      decel = 0.99;
      friction = 0.002;
      min_velocity = 0.6;
      interval_ms = 8;
      delta_multiplier = 1.25;
      velocity_relevance_ms = 100;
      min_sample_ms = 5;
      max_velocity_samples = 5;
      disable_in_browser = 1;
      stop_on_target_change = 1;

      # Debug
      debug = 0;
      stop_on_click = 0;
      stop_on_focus = 0;
    };
  };
}
