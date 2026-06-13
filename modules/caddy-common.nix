# Shared Caddy configuration usable by any host that enables Caddy.
# Provides the (security-headers) snippet plus the Cloudflare DNS-01
# wiring so every node self-issues its own *.niko.ink certificates
# (no public IP / port-80 reachability required). The CLOUDFLARE_API_TOKEN
# referenced by acme_dns is supplied per host via
# services.caddy.environmentFile (a sops secret).
{...}: {
  nixos = {
    config,
    lib,
    pkgs,
    ...
  }: {
    config = lib.mkIf config.services.caddy.enable {
      services.caddy.package = pkgs.caddy.withPlugins {
        plugins = ["github.com/caddy-dns/cloudflare@v0.2.4"];
        hash = "sha256-8yZDrejNKsaUnUaTUFYbarWNmxafqp2z2rWo+XRsxV8=";
      };

      services.caddy.globalConfig = ''
        acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
      '';

      # mkBefore so the snippet is declared earlier in the generated
      # Caddyfile than any vhost that `import`s it.
      services.caddy.extraConfig = lib.mkBefore ''
        (security-headers) {
          header {
            X-Content-Type-Options "nosniff"
            X-Frame-Options "SAMEORIGIN"
            Referrer-Policy "strict-origin-when-cross-origin"
            Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()"
            Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
            -Server
          }
        }
      '';
    };
  };
}
