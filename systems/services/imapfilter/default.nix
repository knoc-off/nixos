{ inputs, config, pkgs, ... }:

let
  # Get all .lua files from the filters directory
  filterFiles = builtins.filter (n: builtins.match ".*\\.lua" n != null)
    (builtins.attrNames (builtins.readDir ./filters));

  # Create a list of paths to all .lua files
  filterPaths = map (file: ./filters + "/${file}") filterFiles;

  # Script to combine all config files
  combineConfigs = pkgs.writeShellScript "combine-configs.sh" ''
    temp=$(mktemp)
    cat ${config.sops.secrets."services/imap/imapfilter_config".path} ${builtins.toString filterPaths} > "$temp"
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

  # Ensure required packages are installed
  environment.systemPackages = with pkgs; [ imapfilter sops ];

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

  # Might want to disable this
  systemd.timers.imapfilter = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "2m";
      Unit = "imapfilter.service";
    };
  };
}
