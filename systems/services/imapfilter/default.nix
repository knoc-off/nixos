{ inputs, config, pkgs, ... }:

let
  filterConfigs = import ./filter-concat.nix { inherit pkgs; };

  combineConfigs = pkgs.writeShellScript "combine-configs.sh" ''
    #temp=$(mktemp)
    temp="/tmp/imapfilter-config"
    cat ${config.sops.secrets."services/imap/imapfilter-config".path} ${
      config.sops.secrets."services/imap/global-variables".path
    } ${filterConfigs}/concatenated_filters.lua > "$temp"
    echo "$temp"
  '';

in {
  sops.secrets = {
    "services/imap/imapfilter-config" = { };
    "services/imap/global-variables" = { };
  };

  systemd.services.imapfilter = {
    description = "IMAPFilter mail filtering service";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        "${pkgs.bash}/bin/bash -c '${pkgs.imapfilter}/bin/imapfilter -c $(${combineConfigs})'";
      User = "root";
    };
  };

  # dont run every 2 minutes, the imap filter service has a daemon mode already
  #systemd.timers.imapfilter = {
  #  wantedBy = [ "timers.target" ];
  #  timerConfig = {
  #    OnBootSec = "2m";
  #    OnUnitActiveSec = "2m";
  #    Unit = "imapfilter.service";
  #  };
  #};
}
