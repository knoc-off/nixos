{config, pkgs, ...}: {
  services.crowdsec = {
    enable = true;
    autoUpdateService = true;

    settings = {
      # Enable the Local API so the agent and bouncers can communicate.
      # Port 8081 because Trilium uses the default 8080.
      # Credentials are auto-generated on first start.
      general.api.server = {
        enable = true;
        listen_uri = "127.0.0.1:8081";
      };
      lapi.credentialsFile = "/var/lib/crowdsec/state/local_api_credentials.yaml";
      capi.credentialsFile = "/var/lib/crowdsec/state/online_api_credentials.yaml";
    };

    hub.collections = [
      "crowdsecurity/caddy"
      "crowdsecurity/sshd"
      "crowdsecurity/linux"
      "crowdsecurity/base-http-scenarios"
    ];

    localConfig = {
      acquisitions = [
        {
          filenames = ["/var/log/caddy/access-*.log"];
          labels.type = "caddy";
        }
        {
          source = "journalctl";
          journalctl_filter = ["_SYSTEMD_UNIT=sshd.service"];
          labels.type = "syslog";
        }
        {
          filenames = ["/var/log/authelia/authelia.log"];
          labels.type = "authelia";
        }
      ];

      # Custom Authelia parser -- extracts remote_ip and message from
      # Authelia's logrus-style text format.
      parsers.s01Parse = [
        {
          name = "custom/authelia-logs";
          description = "Parse Authelia logrus text log lines";
          filter = "evt.Line.Labels.type == 'authelia'";
          onsuccess = "next_stage";
          nodes = [
            {
              grok = {
                pattern = ''time="%{TIMESTAMP_ISO8601:timestamp}" level=%{WORD:log_level} msg="%{DATA:msg}"'';
                apply_on = "message";
              };
            }
            {
              grok = {
                pattern = ''remote_ip=%{IP:source_ip}'';
                apply_on = "message";
              };
              statics = [
                {
                  meta = "source_ip";
                  expression = "evt.Parsed.source_ip";
                }
              ];
            }
          ];
        }
      ];

      # Custom Authelia scenario -- triggers on repeated failed login attempts
      scenarios = [
        {
          type = "leaky";
          name = "custom/authelia-bf";
          description = "Detect Authelia brute force attempts";
          filter = "evt.Parsed.log_level == 'error' && evt.Parsed.msg contains 'Unsuccessful'";
          leakspeed = "30s";
          capacity = 2;
          groupby = "evt.Meta.source_ip";
          blackhole = "5m";
          labels = {
            type = "authelia_bruteforce";
            remediation = true;
          };
        }
      ];

      # Aggressive ban profile -- 24h base, repeat offenders get longer
      profiles = [
        {
          name = "default_ip_remediation";
          filters = ["Alert.Remediation == true && Alert.GetScope() == \"Ip\""];
          decisions = [
            {
              type = "ban";
              duration = "24h";
            }
          ];
          on_success = "break";
        }
      ];
    };
  };

  # Firewall-level blocking via nftables. The Hetzner kernel has
  # nf_tables but lacks ip_set and some nft expression modules (nft_ct,
  # nft_log), so we can't use iptables mode or enable the full NixOS
  # nftables firewall. set-only=false lets the bouncer create its own
  # table/chain/set via netlink without needing networking.nftables.
  services.crowdsec-firewall-bouncer = {
    enable = true;
    registerBouncer.enable = true;
    settings = {
      mode = "nftables";
      api_url = "http://127.0.0.1:8081/";
      nftables.ipv4.set-only = false;
      nftables.ipv6.set-only = false;
    };
  };

  # CrowdSec needs to read Caddy and Authelia log files
  systemd.services.crowdsec.serviceConfig.SupplementaryGroups = [
    "caddy"
    "authelia-main"
  ];
}
