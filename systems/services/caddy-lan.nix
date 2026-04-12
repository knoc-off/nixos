# LAN-local Caddy so clients on home WiFi can reach services without
# running WireGuard themselves. Vhosts are derived from the shared
# wireguard-network.lanServices attrset: services with a localBackend
# are reverse-proxied locally; the rest go through the (hub-proxy)
# snippet which forwards them transparently over WG so they arrive
# at the hub from a trusted source IP and skip public OAuth. All
# client-facing certs are synced from the hub by cert-sync.
{
  self,
  config,
  lib,
  ...
}: let
  cfg = config.services.wireguard-network;

  mkVhost = host: svc: {
    extraConfig = ''
      import lan-cert ${host}
      import security-headers
      ${
        if svc.localBackend != null
        then "reverse_proxy ${svc.localBackend}"
        else "import hub-proxy"
      }
    '';
  };
in {
  imports = [self.nixosModules.services.caddy-common];

  services.caddy = {
    enable = true;
    email = "acme@niko.ink";

    logFormat = ''
      output file /var/log/caddy/access.log {
        roll_size 50MiB
        roll_keep 5
      }
      format json
    '';

    # {host} resolves to the incoming request's Host header at request
    # time, so one hub-proxy snippet serves every proxied vhost. lan-cert
    # uses the snippet-arg placeholder {args.0} which is substituted
    # from `import lan-cert <hostname>` at each call site.
    extraConfig = ''
      (hub-proxy) {
        reverse_proxy https://${cfg.hubIp} {
          header_up Host {host}
          transport http {
            tls_server_name {host}
          }
        }
      }

      (lan-cert) {
        tls /var/lib/caddy-certs/{args.0}.crt /var/lib/caddy-certs/{args.0}.key
      }
    '';
  };

  services.caddy.virtualHosts = lib.mkMerge [
    (lib.mapAttrs mkVhost cfg.lanServices)
    {
      # Drop anything else that hits port 443 on the gateway
      ":443".extraConfig = ''
        tls internal
        abort
      '';
    }
  ];

  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0750 caddy caddy -"
  ];
}
