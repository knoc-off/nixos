{
  inputs,
  pkgs,
  lib,
  mainMod ? "SUPER",
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
  hyprlandPlugins = pkgs.hyprlandPlugins.override {
    hyprland = inputs.hyprnix.packages.${system}.hyprland;
  };

  package = hyprlandPlugins.mkHyprlandPlugin (finalAttrs: {
    pluginName = "scrolloverview";
    version = "0.1-unstable-2026-08-02";

    src = pkgs.fetchFromGitHub {
      owner = "yayuuu";
      repo = "hyprland-scroll-overview";
      rev = "16eb0f851faa308ce3e4a982316ffc8f3d2a2085";
      hash = "sha256-TWUKtHT/RoF5EqETCPyZZiyVVOUzZRHottpHAaE0El4=";
    };

    # The version header is generated from git at build time; the sandboxed
    # fetchFromGitHub source has no .git, so pin the version explicitly to avoid
    # an "unknown" fallback.
    env.SCROLLOVERVIEW_BUILD_VERSION = "16eb0f851faa";

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
