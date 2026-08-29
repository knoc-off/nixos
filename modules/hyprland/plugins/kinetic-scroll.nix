{
  pkgs,
  upkgs,
  lib,
  ...
}:
let
  # Built against upkgs' hyprland to match scroll-overview and the compositor
  # itself -- plugins must link the exact hyprland they load into.
  inherit (upkgs) hyprlandPlugins;

  package = hyprlandPlugins.mkHyprlandPlugin (_: {
    pluginName = "hypr-kinetic-scroll";
    version = "0.2.0-unstable-2026-07-28";

    src = pkgs.fetchFromGitHub {
      owner = "savonovv";
      repo = "hypr-kinetic-scroll";
      rev = "657a8a7cb1cc0a24a06e2dc0947df3e8f4e729ca";
      hash = "sha256-2RI9RSoXhri9tr9DAsB/Zen96DzKsj/wLRbQQKEZ1Yc=";
    };

    # Two upstream bugs that together stop momentum from ever engaging here:
    #
    # 1. Finger-lift (frame) detection is wired only for pointer nodes flagged
    #    m_isTouchpad. This laptop's PixArt pixa3854 delivers FINGER-source
    #    scroll through a node that is not flagged, so upstream never sees the
    #    lift and discards all momentum as "gestureIdle".
    # 2. registerTouchpadCallbacks() runs once in PLUGIN_INIT, which happens
    #    before Hyprland finishes enumerating input devices -- so at boot it
    #    attaches zero listeners and the plugin is silently inert until the
    #    plugin is manually reloaded.
    #
    # both are device-support bugs maybe sendupstream
    patches = [ ./patches/kinetic-scroll-device-callbacks.patch ];

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
          disabled_classes      = "slack",
          stop_on_target_change = 1,
          stop_on_click         = 1,
          stop_on_focus         = 1,
          debug                 = 0,
        },
      },
    })
  '';
}
