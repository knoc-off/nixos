# Slack desktop app + its per-window key layer.
{self, ...}: {
  home = {
    config,
    lib,
    pkgs,
    upkgs,
    ...
  }: let
    inherit (self.lib.keyLayers) presets;
  in {
    home.packages = [upkgs.slack];

    # caps-held shortcuts when a Slack window is focused.
    keyLayers.layers.slack = lib.mkIf config.keyLayers.enable {
      classes = ["slack" "Slack"];
      capsbinds = {
        ctrl = presets.appCtrlKeys;
        keys = presets.navKeys // {g = presets.docNavG;};
      };
    };
  };
}
