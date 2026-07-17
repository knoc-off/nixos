{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  upkgs = inputs.nixpkgs-unstable.legacyPackages.${pkgs.system};
in {
  services.crowdsec = {
    enable = true;
    package = upkgs.crowdsec;
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
      parsers.s02Enrich = [
        {
          name = "custom/tailnet-whitelist";
          description = "Whitelist trusted tailnet subnets";
          whitelist = {
            reason = "Trusted tailnet peer";
            cidr = ["100.64.0.0/10" "fd7a:115c:a1e0::/48"];
          };
        }
      ];

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

  # The bouncer races crowdsec at boot, exits 1 before LAPI is up.
  systemd.services.crowdsec-firewall-bouncer = {
    after = ["crowdsec.service"];
    requires = ["crowdsec.service"];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  systemd.services.crowdsec.serviceConfig.SupplementaryGroups = [
    "caddy"
  ];

  # ────────────────────────────────────────────────────────────────────────
  # Fix a nixpkgs incompatibility between the crowdsec agent and the firewall
  # bouncer's auto-register unit.
  #
  # The agent creates /var/lib/crowdsec as a *real* directory via tmpfiles and
  # writes to it as uid 988 through ReadWritePaths + PrivateUsers=true (no
  # StateDirectory). The register unit instead declares
  # `StateDirectory = "crowdsec-firewall-bouncer-register crowdsec"`; that
  # second `crowdsec` entry, with DynamicUser=yes, makes systemd convert
  # /var/lib/crowdsec into a /var/lib/private/crowdsec symlink and re-own the
  # whole tree (including crowdsec.db) — crash-looping the agent with
  # "mkdir /var/lib/crowdsec: permission denied".
  #
  # Give the register DB access the same way the agent has it: drop the
  # `crowdsec` StateDirectory entry (keeping only its own), grant write via
  # ReadWritePaths, and map crowdsec -> uid 988 with PrivateUsers=true.
  systemd.services.crowdsec-firewall-bouncer-register.serviceConfig = {
    StateDirectory = lib.mkForce "crowdsec-firewall-bouncer-register";
    ReadWritePaths = ["/var/lib/crowdsec"];
    PrivateUsers = true;
  };

  # cscli defaults to reading /etc/crowdsec/config.yaml, but the agent module
  # runs with `-c <store>/crowdsec.yaml` and never creates that file — so the
  # register unit's raw `cscli bouncers add/list` calls can't find the LAPI DB
  # path. Symlink the config (byte-identical to what the agent runs) at the
  # default path. A tmpfiles symlink drops in just this one file without taking
  # over the crowdsec-owned /etc/crowdsec directory (which holds writable hub
  # data).
  systemd.tmpfiles.rules = [
    "L+ /etc/crowdsec/config.yaml - - - - ${
      (pkgs.formats.yaml {}).generate "crowdsec.yaml" config.services.crowdsec.settings.general
    }"
  ];
}
