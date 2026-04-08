{config, pkgs, ...}: {
  services.crowdsec = {
    enable = true;
    autoUpdateService = true;

    settings = {
      # port 8081 -- Trilium occupies 8080
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
      ];

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

  # nftables mode -- kernel has nf_tables but lacks ip_set and nft_ct/nft_log,
  # so iptables mode and networking.nftables both fail. set-only=false lets
  # the bouncer create its own table via netlink.
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

  systemd.services.crowdsec.serviceConfig.SupplementaryGroups = [
    "caddy"
  ];
}
