{ inputs, config, pkgs, ... }:

let
  # Non-sensitive part of the configuration
  imapfilterPublicConfig = pkgs.writeText "config_public.lua" ''
    -- Your filter rules go here
    messages = account.INBOX:contain_from('noreply@bitwarden.com')
    messages:move_messages(account['Processed'])

    -- Add more filter rules as needed
  '';

  combineConfigs = pkgs.writeShellScript "combine-configs.sh" ''
    temp=$(mktemp)
    cat ${
      config.sops.secrets."services/imap/imapfilter_config".path
    } ${imapfilterPublicConfig} > "$temp"
    echo "$temp"
  '';
in {
  imports = [

    {
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

    }

  ];

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

  systemd.timers.imapfilter = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "2m";
      Unit = "imapfilter.service";
    };
  };
}
