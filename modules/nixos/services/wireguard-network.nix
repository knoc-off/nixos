# Thin wrapper around WireGuard networking plumbing. Generates dnsmasq
# split DNS, Caddy lan-only snippet, CrowdSec whitelist, IP forwarding,
# and systemd ordering from a shared set of options. Does NOT generate
# the WireGuard interface itself -- each host defines its own peers and
# keys explicitly via networking.wireguard.interfaces.
{
  config,
  lib,
  ...
}: let
  cfg = config.services.wireguard-network;
in {
  options.services.wireguard-network = {
    enable = lib.mkEnableOption "WireGuard VPN network plumbing";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Base domain for service subdomains (e.g. niko.ink).";
    };

    subnet = lib.mkOption {
      type = lib.types.str;
      description = "WireGuard VPN subnet in CIDR notation.";
    };

    trustedSubnets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "Subnets allowed through the Caddy lan-only gate and CrowdSec whitelist.";
    };

    hubIp = lib.mkOption {
      type = lib.types.str;
      description = "WireGuard IP of the hub node. LAN-only domains resolve here.";
    };

    lanOnlySubdomains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Subdomain prefixes only reachable via trusted subnets (e.g. [\"kitchenowl\" \"notes.api\"]).";
    };

    dns = {
      enable = lib.mkEnableOption "split DNS via dnsmasq for LAN-only domains";

      upstream = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["1.1.1.1" "9.9.9.9"];
        description = "Upstream DNS servers for non-overridden queries.";
      };

      localOnly = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "When true, don't modify system resolv.conf. Use on servers that already have DNS.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Bind dnsmasq to a specific IP (e.g. the WireGuard address). Null means all interfaces.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    # Split DNS -- LAN-only subdomains resolve to the hub's VPN IP
    services.dnsmasq = lib.mkIf cfg.dns.enable {
      enable = true;
      resolveLocalQueries = !cfg.dns.localOnly;
      settings =
        {
          no-resolv = true;
          server = cfg.dns.upstream;
          address = map (sub: "/${sub}.${cfg.domain}/${cfg.hubIp}") cfg.lanOnlySubdomains;
        }
        // lib.optionalAttrs (cfg.dns.listenAddress != null) {
          listen-address = cfg.dns.listenAddress;
          bind-interfaces = true;
        };
    };

    systemd.services.dnsmasq = lib.mkIf cfg.dns.enable {
      # dnsmasq may bind to a WireGuard IP that doesn't exist until wg0 is up
      after = ["wireguard-wg0.service"];
      wants = ["wireguard-wg0.service"];
      serviceConfig = {
        Restart = lib.mkDefault "always";
        RestartSec = lib.mkDefault "5s";
      };
    };

    # DNS port only on the WireGuard interface (not public)
    networking.firewall.interfaces.wg0.allowedUDPPorts =
      lib.mkIf (cfg.dns.enable && cfg.dns.listenAddress != null) [53];

    # Caddy: inject (lan-only) snippet when Caddy is present on this host
    services.caddy.extraConfig = lib.mkIf config.services.caddy.enable (lib.mkAfter ''
      (lan-only) {
        @denied not remote_ip ${lib.concatStringsSep " " cfg.trustedSubnets} 127.0.0.1
        abort @denied
      }
    '');

    # CrowdSec: whitelist trusted subnets when CrowdSec is present
    services.crowdsec.localConfig.parsers.s02Enrich =
      lib.mkIf config.services.crowdsec.enable [
        {
          name = "custom/wireguard-whitelist";
          description = "Whitelist trusted VPN and LAN subnets";
          whitelist = {
            reason = "Trusted VPN/LAN peer";
            cidr = cfg.trustedSubnets;
          };
        }
      ];
  };
}
