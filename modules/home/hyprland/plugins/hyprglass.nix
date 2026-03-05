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

  hyprglass = hyprlandPlugins.mkHyprlandPlugin (finalAttrs: {
    pluginName = "hyprglass";
    version = "0.2.1-unstable";

    src = pkgs.fetchFromGitHub {
      owner = "hyprnux";
      repo = "hyprglass";
      rev = "0e82595ec5c1b04e30b559fe689f3ceae24bc3ef";
      hash = "sha256-i2NXWuvVM+n6m4kwfqVTUOpinNWJHhSQdzMPbMR/Bn8=";
    };

    dontUseCmakeConfigure = true;

    buildPhase = "make all";

    installPhase = ''
      mkdir -p $out/lib
      cp hyprglass.so $out/lib/libhyprglass.so
    '';

    meta = {
      homepage = "https://github.com/hyprnux/hyprglass";
      description = "Liquid Glass inspired blur/refraction effects for Hyprland";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  });
in {
  wayland.windowManager.hyprland = {
    plugins = [hyprglass];

    settings = {
      windowrule = [
        # Window opacity — makes the glass visible through transparent surfaces
        # "opacity 0.85 override 0.80 override, match:class (kitty|foot|alacritty|wezterm)"
        # "opacity 0.90 override 0.85 override, match:class (firefox|chromium|google-chrome|brave-browser)"
        # "opacity 0.88 override 0.82 override, match:float 1"
        # "opacity 0.85 override 0.80 override, match:class (waybar|eww)"

        # Terminals — subtle glass, dark theme
        "tag +hyprglass_preset_terminal, match:class (kitty|foot|alacritty|wezterm)"
        "tag +hyprglass_theme_dark, match:class (kitty|foot|alacritty|wezterm)"

        # Browsers — default preset, light theme
        "tag +hyprglass_theme_light, match:class (firefox|chromium|google-chrome|brave-browser)"

        # Floating utility windows — richer float preset
        "tag +hyprglass_preset_float, match:float 1"

        # Bars/panels
        "tag +hyprglass_preset_panel, match:class (waybar|eww)"
      ];

      "plugin:hyprglass" = {
        enabled = 1;
        default_theme = "dark";
        default_preset = "default";

        # Global overrides
        blur_strength = 2.0;
        blur_iterations = 3;
        glass_opacity = 1.0;
        edge_thickness = 0.06;
        refraction_strength = 0.5;
        chromatic_aberration = 0.4;
        fresnel_strength = 0.5;
        specular_strength = 0.7;
        lens_distortion = 0.3;

        # Dark theme overrides
        "dark:brightness" = 0.82;
        "dark:contrast" = 0.90;
        "dark:saturation" = 0.80;
        "dark:adaptive_dim" = 0.35;

        # Light theme overrides
        "light:brightness" = 1.12;
        "light:adaptive_boost" = 0.4;

        # Custom presets
        preset = [
          # Subtle terminal preset — light blur, keeps readability
          "name:terminal, blur_strength:1.5, blur_iterations:2, glass_opacity:0.92, refraction_strength:0.3, lens_distortion:0.0"
          "name:terminal:dark, brightness:0.85, contrast:0.95"
          "name:terminal:light, brightness:1.1, contrast:0.92"

          # Panel/bar preset — barely-there glass
          "name:panel, blur_strength:1.2, blur_iterations:2, glass_opacity:0.88, refraction_strength:0.2, edge_thickness:0.04, lens_distortion:0.0"
          "name:panel:dark, brightness:0.80"
          "name:panel:light, brightness:1.08"

          # Floating windows — richer glass
          "name:float, blur_strength:2.5, glass_opacity:0.95, refraction_strength:0.6, chromatic_aberration:0.5"
          "name:float:dark, brightness:0.80, adaptive_dim:0.4"
          "name:float:light, brightness:1.1, adaptive_boost:0.45"
        ];
      };
    };
  };
}
