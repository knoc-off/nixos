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
    version = "0.3.0";

    src = pkgs.fetchFromGitHub {
      owner = "hyprnux";
      repo = "hyprglass";
      rev = "v0.3.0";
      hash = "sha256-4jSLd3ZoTGwO22usSnX2/Y/mAD4o0js8od+UnvZwiW8=";
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
      license = lib.licenses.bsd3;
      platforms = lib.platforms.linux;
    };
  });
in {
  wayland.windowManager.hyprland = {
    plugins = [hyprglass];

    settings = {
      "plugin:hyprglass" = {
        enabled = 1;
        default_theme = "dark";
        default_preset = "default";

        # ── Windows: invisible glass (layers-only mode) ──
        # Global defaults are set to zero so the decoration is a no-op on windows.
        # Layers override these via a dedicated preset below.
        blur_strength = 0.0;
        blur_iterations = 1;
        glass_opacity = 0.0;
        refraction_strength = 0.0;
        chromatic_aberration = 0.0;
        fresnel_strength = 0.0;
        specular_strength = 0.0;
        edge_thickness = 0.0;
        lens_distortion = 0.0;

        # ── Layer surfaces (BETA) ──
        # Glass only on layer surfaces (bars, dock, notifications, OSD, etc.)
        # Empty namespaces = all layers; fully-transparent layers are auto-skipped.
        # Internal noctalia surfaces without screen suffixes are excluded explicitly.
        layers = {
          enabled = 1;
          exclude_namespaces = "noctalia-fade-overlay, noctalia-screen-detector, noctalia-image-cache-renderer";
          preset = "layer-glass";
        };

        # Dark theme overrides (for layers via preset)
        "dark:brightness" = 0.85;
        "dark:contrast" = 0.92;
        "dark:saturation" = 0.85;
        "dark:adaptive_dim" = 0.25;

        # Light theme overrides (for layers via preset)
        "light:brightness" = 1.10;
        "light:adaptive_boost" = 0.35;

        # ── Layer glass preset ──
        # Low blur, high refraction/warping for a liquid-glass look.
        preset = [
          "name:layer-glass, blur_strength:0.4, blur_iterations:1, glass_opacity:0.80, edge_thickness:0.08, refraction_strength:0.9, chromatic_aberration:0.7, fresnel_strength:0.8, specular_strength:0.8, lens_distortion:0.8"
          "name:layer-glass:dark, brightness:0.85, contrast:0.92, saturation:0.85, adaptive_dim:0.20"
          "name:layer-glass:light, brightness:1.10, adaptive_boost:0.35"
        ];
      };
    };
  };
}
