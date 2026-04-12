# Shared Caddy configuration usable by any host that enables Caddy.
# Today just provides the (security-headers) snippet so both the hub
# and LAN-local Caddy instances apply identical headers without copying
# the block into each host's config.
{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.services.caddy.enable {
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
}
