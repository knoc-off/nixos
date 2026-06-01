{ self, ... }: {
  home = { config, lib, pkgs, ... }:
  let
    cfg = config.services.claude-mem;
    system = pkgs.stdenv.hostPlatform.system;
  in {
    options.services.claude-mem = {
      enable = lib.mkEnableOption "claude-mem worker daemon for persistent memory";

      port = lib.mkOption {
        type = lib.types.port;
        default = 37777;
        description = "Port for the claude-mem worker HTTP API.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${system}.claude-mem;
        description = "The claude-mem package to use.";
      };

      opencode.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the claude-mem plugin for OpenCode.";
      };
    };

    config = lib.mkIf cfg.enable {
      home.sessionVariables.CLAUDE_MEM_WORKER_PORT = toString cfg.port;

      # Worker daemon
      systemd.user.services.claude-mem-worker = {
        Unit = {
          Description = "claude-mem persistent memory worker";
          After = [ "network.target" ];
        };
        Service = {
          Type = "simple";
          ExecStart = "${lib.getExe cfg.package} --daemon";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [
            "CLAUDE_MEM_WORKER_PORT=${toString cfg.port}"
            "CLAUDE_MEM_WORKER_HOST=127.0.0.1"
          ];
        };
        Install.WantedBy = [ "default.target" ];
      };

      # Install OpenCode plugin
      xdg.configFile = lib.mkIf cfg.opencode.enable {
        "opencode/plugins/claude-mem.js".source =
          "${cfg.package}/lib/claude-mem/dist/opencode-plugin/index.js";
      };
    };
  };
}
