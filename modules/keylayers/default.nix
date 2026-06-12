# Aggregates per-window key layers contributed by app modules and the user's
# `base` layer, then wires the assembled result into hyprkan + kanata.
#
# App modules (firefox, ghostty, slack, freecad, ...) contribute their slice
# via `keyLayers.layers.<name>`. The layer schema is documented in
# lib/key-layers.nix; shared building blocks live in `self.lib.keyLayers.presets`.
#
# This module deliberately does NOT import the kanata/hyprkan modules, so app
# modules can import it cheaply just to declare a layer. Users who set
# `keyLayers.enable = true` are expected to import those modules themselves
# (which sets the device/port/package specifics the assembly populates).
{self, ...}: {
  home = {
    config,
    lib,
    ...
  }:
  with lib; let
    cfg = config.keyLayers;
    inherit (self.lib.keyLayers) mkKeyLayers;
    kl = mkKeyLayers cfg.layers;
  in {
    options.keyLayers = {
      enable = mkEnableOption "per-window kanata + hyprkan key layers";

      layers = mkOption {
        type = types.attrsOf types.anything;
        default = {};
        description = ''
          Map of layer name to layer definition, merged from app modules and the
          user config. See lib/key-layers.nix for the layer schema. "base" is the
          wildcard fallback for unmatched windows.
        '';
      };

      extraAliases = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra kanata aliases injected into the generated config (host-specific,
          e.g. the application launcher command).
        '';
      };

      kanataKeyboard = mkOption {
        type = types.str;
        default = "main";
        description = "Name of the services.kanata.keyboards entry to populate.";
      };
    };

    config = mkIf cfg.enable {
      assertions = [
        {
          assertion = cfg.layers ? base;
          message = "keyLayers.enable is set but no `base` layer is defined.";
        }
      ];

      programs.hyprkan.rules = kl.hyprkanRules;
      services.kanata.keyboards.${cfg.kanataKeyboard}.config = kl.kanataConfig cfg.extraAliases;
    };
  };
}
