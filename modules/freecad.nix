# FreeCAD + its per-window key layer (the Expression editor sub-window).
{self, ...}: {
  home = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (self.lib.keyLayers) presets;
  in {
    options.programs.freecad.package = lib.mkPackageOption pkgs.upkgs "freecad-wayland" {};

    config = {
      home.packages = [config.programs.freecad.package];

      # The FreeCAD Expression editor benefits from caps-held shortcuts plus
      # tab/shift-tab moving through the completion list.
      keyLayers.layers.freecadExprEditor = lib.mkIf config.keyLayers.enable {
        matchers = [
          {
            class = "org.freecad.FreeCAD";
            title = "Expression editor";
          }
        ];
        capsbinds = {
          ctrl = presets.appCtrlKeys;
          keys = presets.navKeys // {g = presets.docNavG;};
        };
        binds = {
          tab = {
            default = "down";
            shift = "up";
          };
        };
      };
    };
  };
}
