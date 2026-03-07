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

      friction = 0.009;
      decel = 0.99;
      min_velocity = 0.45;
      interval_ms = 8;
      delta_multiplier = 1.0;
      velocity_relevance_ms = 70;
      min_sample_ms = 6;
      max_velocity_samples = 6;

      disable_in_browser = 1;
      stop_on_target_change = 1;
      stop_on_click = 1;
      stop_on_focus = 1;

      debug = 0;
    };
  };
}
