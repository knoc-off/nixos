# lspmux - LSP multiplexer config file generation
# macOS: ~/Library/Application Support/lspmux/config.toml
# Linux: ~/.config/lspmux/config.toml
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.lspmux;
  tomlFormat = pkgs.formats.toml {};
  configFile = tomlFormat.generate "lspmux-config" cfg.settings;
in {
  options.services.lspmux = {
    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {};
      description = ''
        lspmux configuration options (converted to TOML).
        See https://codeberg.org/p2502/lspmux for available options.
      '';
      example = lib.literalExpression ''
        {
          instance_timeout = 300;
          gc_interval = 10;
          listen = ["127.0.0.1" 27631];
          log_filters = "info";
          pass_environment = ["*"];
        }
      '';
    };
  };

  config = lib.mkIf (cfg.settings != {}) {
    # The `directories` crate uses platform-native config paths
    home.file = lib.mkIf pkgs.stdenv.isDarwin {
      "Library/Application Support/lspmux/config.toml".source = configFile;
    };
    xdg.configFile = lib.mkIf (!pkgs.stdenv.isDarwin) {
      "lspmux/config.toml".source = configFile;
    };
  };
}
