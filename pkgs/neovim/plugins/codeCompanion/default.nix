{ lib, pkgs, ... }:
{
  name = "codeCompanion";
  originalName = "codeCompanion";
  maintainers = [ "knoff" ];
  package = "codecompanion-nvim";

  settingsDescription = ''
    Configuration options for CodeCompanion plugin.
  '';

  settingsOptions = {
    # Add your plugin's specific settings here
    enable = lib.mkEnableOption "Enable CodeCompanion plugin";
  };

  callSetup = true; # Set to true if your plugin uses a setup function

  extraOptions = {
    # Add any additional configuration options here
  };

  extraConfig = cfg: {
    plugins.codeCompanion.luaConfig.content = lib.mkIf cfg.enable ''
      require('codecompanion').setup({
        -- Your default configuration here
      })
    '';
  };
}
