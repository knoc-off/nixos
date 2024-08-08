{ inputs, config, pkgs, ... }:

let
  filterConfigs = import ./filter-concat.nix { inherit pkgs; };

  combineConfigs = pkgs.writeShellScript "combine-configs.sh" ''
    #temp=$(mktemp)
    temp="/tmp/imapfilter_config"
    cat ${config.sops.secrets."services/imap/imapfilter_config".path} ${filterConfigs}/concatenated_filters.lua > "$temp"
    echo "$temp"
  '';

in {
  sops.secrets = { "services/imap/imapfilter_config" = { }; };
  # EXAMPLE YAML:
  #  services:
  #      imap:
  #          imapfilter_config: |
  #              account = IMAP {
  #                server = 'imap.example.com',
  #                username = 'me@example.com',
  #                password = 'pa$$w0rd',
  #              }

  systemd.services.imapfilter = {
    description = "IMAPFilter mail filtering service";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.imapfilter}/bin/imapfilter -c $(${combineConfigs})'";
      User = "root";
    };
  };

  systemd.timers.imapfilter = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "2m";
      Unit = "imapfilter.service";
    };
  };
}
