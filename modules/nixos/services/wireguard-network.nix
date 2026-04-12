# Generates dnsmasq split DNS, Caddy lan-only snippet, CrowdSec whitelist,
# IP forwarding, and dnsmasq ordering. WireGuard interfaces are defined
# explicitly per-host.
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

    lanServices = lib.mkOption {
      default = {};
      description = ''
        Services exposed on the home LAN. Keys are subdomain prefixes
        without the base domain (e.g. "home", "kitchenowl"). Drives four
        downstream configurations from a single source of truth:
          - hub dnsmasq rewrites each host to the hub WG IP for VPN clients
          - gateway dnsmasq rewrites each host to its own LAN IP for
            clients on home WiFi
          - gateway Caddy terminates TLS for each host (reverse-proxies
            locally if localBackend is set, otherwise forwards to the hub
            over WG so the request arrives from a trusted source and
            skips public auth)
          - hub cert-sync ships each service's cert/key to the gateway
      '';
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          localBackend = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "localhost:8123";
            description = ''
              When set, the home gateway's Caddy reverse-proxies this
              service to the given address on its local host (used for
              services physically hosted on the gateway). When null,
              the gateway transparently forwards the service to the
              hub over WireGuard.
            '';
          };
        };
      });
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

      lanOnlyAnswer = lib.mkOption {
        type = lib.types.str;
        default = cfg.hubIp;
        defaultText = lib.literalExpression "config.services.wireguard-network.hubIp";
        description = ''
          IP that dnsmasq returns for the rewritten LAN-only subdomains.
          Defaults to the WG hub IP, which is correct for remote VPN clients
          reaching services through the hub. Override on a host whose
          dnsmasq serves LAN clients that cannot reach the hub IP directly
          (e.g. the home gateway returning its own LAN IP so WiFi clients
          can reach a locally hosted service without running WireGuard).
        '';
      };

      rewriteHosts = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.attrNames cfg.lanServices;
        defaultText = lib.literalExpression "lib.attrNames config.services.wireguard-network.lanServices";
        description = ''
          Full hostnames this host's dnsmasq rewrites to lanOnlyAnswer.
          Defaults to every key in lanServices. Override on hosts that
          should only rewrite a subset (e.g. a gateway that hosts only
          some services locally and lets the rest resolve to the hub's
          public address as normal).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    services.dnsmasq = lib.mkIf cfg.dns.enable {
      enable = true;
      resolveLocalQueries = !cfg.dns.localOnly;
      settings =
        {
          no-resolv = true;
          server = cfg.dns.upstream;
          address = map (host: "/${host}/${cfg.dns.lanOnlyAnswer}") cfg.dns.rewriteHosts;
        }
        // lib.optionalAttrs (cfg.dns.listenAddress != null) {
          listen-address = cfg.dns.listenAddress;
          bind-interfaces = true;
        };
    };

    systemd.services.dnsmasq = lib.mkIf cfg.dns.enable {
      # wg0 must exist before dnsmasq if listenAddress is a WG IP
      after = ["wireguard-wg0.service"];
      wants = ["wireguard-wg0.service"];
      serviceConfig = {
        Restart = lib.mkDefault "always";
        RestartSec = lib.mkDefault "5s";
      };
    };

    networking.firewall.interfaces.wg0.allowedUDPPorts =
      lib.mkIf (cfg.dns.enable && cfg.dns.listenAddress != null) [53];

    services.caddy.extraConfig = lib.mkIf config.services.caddy.enable (lib.mkAfter ''
      (lan-only) {
        @denied not remote_ip ${lib.concatStringsSep " " cfg.trustedSubnets} 127.0.0.1
        abort @denied
      }
    '');

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
