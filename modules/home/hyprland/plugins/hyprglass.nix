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
        "dark:brightness" = 0.82;
        "dark:contrast" = 0.90;
        "dark:saturation" = 0.80;
        "dark:adaptive_dim" = 0.35;

        # Light theme overrides (for layers via preset)
        "light:brightness" = 1.12;
        "light:adaptive_boost" = 0.4;

        # ── Layer glass preset ──
        # All the actual effect values live here so only layers get them.
        preset = [
          "name:layer-glass, blur_strength:2.0, blur_iterations:3, glass_opacity:1.0, edge_thickness:0.06, refraction_strength:0.5, chromatic_aberration:0.4, fresnel_strength:0.5, specular_strength:0.7, lens_distortion:0.3"
          "name:layer-glass:dark, brightness:0.82, contrast:0.90, saturation:0.80, adaptive_dim:0.35"
          "name:layer-glass:light, brightness:1.12, adaptive_boost:0.4"
        ];
      };
    };
  };
}
