{ config, lib, pkgs, ... }:

let
  cfg = config.services.gateService;
  settingsFormat = pkgs.formats.yaml { };
in {
  options.services.gateService = {
    enable = lib.mkEnableOption "Gate Service";
    config = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Configuration for the gate service";
    };
  };

  config = lib.mkIf cfg.enable {
    # add system packages Debugging
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "gateConfigPrint" ''
        cat ${settingsFormat.generate "gate-config.yaml" { inherit (cfg) config; }}
      '')
    ];
    systemd.services.gateService = {
      description = "Gate Service";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.gate}/bin/gate -c ${
            settingsFormat.generate "gate-config.yaml" { inherit (cfg) config; }
          }";
        Restart = "always";
        User = "root";
      };
    };
  };
}
