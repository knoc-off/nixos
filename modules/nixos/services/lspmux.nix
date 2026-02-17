# lspmux - LSP multiplexer service
# Allows multiple neovim instances to share a single language server
{
  config,
  lib,
  pkgs,
  self,
  ...
}:
let
  cfg = config.services.lspmux;

  tomlFormat = pkgs.formats.toml {};
in
{
  options.services.lspmux = {
    enable = lib.mkEnableOption "lspmux LSP multiplexer";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.lspmux;
      description = "The lspmux package to use";
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {};
      description = ''
        lspmux configuration options (converted to TOML).
        See https://codeberg.org/p2502/lspmux for available options.
      '';
      example = lib.literalExpression ''
        {
          instance_timeout = 300;  # 5 minutes
          gc_interval = 10;
          listen = ["127.0.0.1" 27631];
          log_filters = "info";
          pass_environment = ["*"];
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.lspmux = {
      description = "Language server multiplexer";
      wantedBy = ["default.target"];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/lspmux server";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    environment.systemPackages = [cfg.package];
  };
}
