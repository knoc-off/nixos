# lspmux - LSP multiplexer service (macOS/launchd)
# Allows multiple neovim instances to share a single language server
{
  config,
  lib,
  pkgs,
  self,
  ...
}: let
  cfg = config.services.lspmux;
in {
  options.services.lspmux = {
    enable = lib.mkEnableOption "lspmux LSP multiplexer";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.lspmux;
      description = "The lspmux package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    launchd.user.agents.lspmux = {
      serviceConfig = {
        Label = "org.codeberg.p2502.lspmux";
        ProgramArguments = ["${cfg.package}/bin/lspmux" "server"];
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/lspmux.log";
        StandardErrorPath = "/tmp/lspmux.log";
      };
    };

    environment.systemPackages = [cfg.package];
  };
}
