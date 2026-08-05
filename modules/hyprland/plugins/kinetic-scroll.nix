{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  hyprlandPlugins = pkgs.hyprlandPlugins.override {
    hyprland = inputs.hyprnix.packages.${system}.hyprland;
  };

  package = hyprlandPlugins.mkHyprlandPlugin (finalAttrs: {
    pluginName = "hypr-kinetic-scroll";
    version = "0.2.0-unstable-2026-07-28";

    src = pkgs.fetchFromGitHub {
      owner = "savonovv";
      repo = "hypr-kinetic-scroll";
      rev = "657a8a7cb1cc0a24a06e2dc0947df3e8f4e729ca";
      hash = "sha256-2RI9RSoXhri9tr9DAsB/Zen96DzKsj/wLRbQQKEZ1Yc=";
    };

    # Wire finger-lift (frame) detection for pointer nodes Hyprland does not flag
    # m_isTouchpad. This laptop's touchpad delivers FINGER-source scroll through
    # such a node, so upstream never sees the lift and discards all momentum.
    patches = [ ./patches/kinetic-scroll-frame-all-pointers.patch ];

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
in
{
  inherit package;

  lua = ''
    hl.plugin.load("${package}/lib/libhypr-kinetic-scroll.so")

    hl.config({
      plugin = {
        kinetic_scroll = {
          enabled               = 1,
          decel                 = 0.93,
          min_velocity          = 0.45,
          interval_ms           = 8,
          delta_multiplier      = 1.0,
          disable_in_browser    = 1,
          stop_on_target_change = 1,
          stop_on_click         = 1,
          stop_on_focus         = 1,
          debug                 = 0,
        },
      },
    })
  '';
}
