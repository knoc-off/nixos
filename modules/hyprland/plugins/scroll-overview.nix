{
  pkgs,
  upkgs,
  lib,
  mainMod ? "SUPER",
  ...
}: let
  # Third-party hypr plugins track Hyprland HEAD, not releases, so they need
  # the newest hyprland available -- against stable's 0.55.4 this fails to
  # compile on moved headers (hyprland/src/output/Monitor.hpp) and a changed
  # CHyprColor signature. upkgs carries 0.56.2, which it builds against.
  inherit (upkgs) hyprlandPlugins;

  package = hyprlandPlugins.mkHyprlandPlugin (finalAttrs: {
    pluginName = "scrolloverview";
    version = "0.1-unstable-2026-08-27";

    src = pkgs.fetchFromGitHub {
      owner = "yayuuu";
      repo = "hyprland-scroll-overview";
      rev = "f9248ab6bee770e9d68813b48cc6ca12b3271254";
      hash = "sha256-SEa8XQtrNg90AUeZFE9+lGvYEWd0T2ht/+sKx+kWUak=";
    };

    # The version header is generated from git at build time; the sandboxed
    # fetchFromGitHub source has no .git, so pin the version explicitly to avoid
    # an "unknown" fallback.
    env.SCROLLOVERVIEW_BUILD_VERSION = "f9248ab6bee7";

    nativeBuildInputs = with pkgs; [cmake];

    buildInputs = with pkgs; [
      pango
      cairo
      lua5_4
    ];

    meta = {
      homepage = "https://github.com/yayuuu/hyprland-scroll-overview";
      description = "Scrollable overview plugin for Hyprland";
      license = lib.licenses.bsd3;
      platforms = lib.platforms.linux;
    };
  });
in {
  inherit package;

  lua = ''
    hl.plugin.load("${package}/lib/libscrolloverview.so")

    hl.config({
      plugin = {
        scrolloverview = {
          gesture_distance = 300,
          scale = 0.5,
          workspace_gap = 100,
          input = {
            touchpad_scroll_factor = 7,
          },
        },
      },
    })

    -- hl.plugin.load() is deferred: the scrolloverview namespace does not exist
    -- during the first config pass, so calling it unguarded throws and aborts
    -- the eval before Hyprland loads the plugin. Guard it so the pass completes;
    -- the gesture registers on the post-load reload once the namespace exists.
    if hl.plugin.scrolloverview then
      hl.plugin.scrolloverview.gesture({ fingers = 4, direction = "up" })
    end

    hl.bind("${mainMod} + TAB", function()
      hl.plugin.scrolloverview.overview("toggle")
    end)
  '';
}
