# LAN-local Caddy on the Pi. It terminates TLS for home.niko.ink (Home
# Assistant runs here) using a DNS-01 cert issued by security.acme (see
# caddy-common). Tailnet clients resolve home.niko.ink to this node's
# tailnet IP through Headscale MagicDNS; the other service names resolve
# straight to the hub
{
  self,
  ...
}:
{
  imports = [ self.nixosModules.caddy-common ];

  services.caddy = {
    enable = true;

    logFormat = ''
      output file /var/log/caddy/access.log {
        roll_size 50MiB
        roll_keep 5
      }
      format json
    '';

    virtualHosts."home.niko.ink" = {
      useACMEHost = "home.niko.ink";
      extraConfig = ''
        import security-headers
        reverse_proxy localhost:8123
      '';
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0750 caddy caddy -"
  ];
}
