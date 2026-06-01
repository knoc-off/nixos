{ pkgs, lib, config, self, ... }:
let
  cfg = config.services.host-query;
  system = pkgs.stdenv.hostPlatform.system;
in {
  options.services.host-query = {
    enable = lib.mkEnableOption "host-query plugin for jailed OpenCode agents";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${system}.host-query;
      description = "The host-query package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    xdg.configFile."opencode/plugins/host-query.js".source =
      "${cfg.package}/lib/host-query/plugin/index.js";
  };
}
