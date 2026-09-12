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

    # z2m frontend: token-gated (frontend.auth_token, set via env in
    # home-assistant.nix), only reachable through here. Shares the Pi's cert
    # as a SAN rather than issuing a second one.
    virtualHosts."z2m.niko.ink" = {
      useACMEHost = "home.niko.ink";
      extraConfig = ''
        import security-headers
        reverse_proxy localhost:7768
      '';
    };
  };

  security.acme.certs."home.niko.ink".extraDomainNames = [ "z2m.niko.ink" ];

  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0750 caddy caddy -"
  ];
}
