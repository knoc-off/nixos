# LAN-local Caddy on the Pi. It terminates TLS for home.niko.ink (Home
# Assistant runs here) using a self-issued DNS-01 wildcard-capable cert
# (via caddy-common). Tailnet clients resolve home.niko.ink to this node's
# tailnet IP through Headscale MagicDNS; the other service names resolve
# straight to the hub, so the Pi no longer proxies anything.
{
  self,
  config,
  lib,
  ...
}: {
  imports = [self.nixosModules.caddy-common];

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

    virtualHosts."home.niko.ink".extraConfig = ''
      import security-headers
      reverse_proxy localhost:8123
    '';
  };

  services.caddy.environmentFile = config.sops.secrets."services/caddy/cloudflare-env".path;
  sops.secrets."services/caddy/cloudflare-env" = {};

  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0750 caddy caddy -"
  ];
}
