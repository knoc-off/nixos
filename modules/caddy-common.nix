# Shared Caddy configuration usable by any host that enables Caddy.
# Provides the (security-headers) snippet plus the Cloudflare DNS-01 wiring so
# every node issues its own niko.ink certificates (no public IP / port-80
# reachability required).
#
# Certificates come from security.acme (lego), not from Caddy itself. Caddy's
# own DNS-01 needs the caddy-dns/cloudflare plugin, which means
# pkgs.caddy.withPlugins -- a fixed-output derivation whose builder runs
# `xcaddy` + `go mod vendor` against the live Go module proxy. Its output hash
# therefore depends on pkgs.go and pkgs.xcaddy, neither of which can be pinned
# from here, so every nixpkgs bump that moves the Go toolchain rerolls the hash
# and breaks the autobuild for every host at once. lego is an ordinary Go
# package with a pinned vendorHash and no such drift, and the caddy module
# already knows how to consume its output via virtualHosts.<name>.useACMEHost.
#
# Each host names its own cert (see the useACMEHost call sites) rather than
# sharing one wildcard: identical domain sets across hosts would race against
# Let's Encrypt's 5-duplicate-certificates-per-week limit, and it keeps each
# node's private key scoped to the names it actually serves.
{ ... }: {
  nixos =
    {
      config,
      lib,
      ...
    }:
    {
      config = lib.mkIf config.services.caddy.enable {
        # Every host that enables Caddy needs the same token, so declare the
        # secret here rather than repeating it per host. The caddy module
        # supplies the rest of each cert (group, reloadServices) automatically
        # for any name referenced by useACMEHost.
        sops.secrets."services/caddy/cloudflare-env" = { };

        security.acme = {
          acceptTerms = true;
          defaults = {
            email = "acme@niko.ink";
            dnsProvider = "cloudflare";
            environmentFile = config.sops.secrets."services/caddy/cloudflare-env".path;

            # Same reason the old Caddy cert_issuer block pinned resolvers: the
            # DNS-01 solver finds the owning zone with an SOA query through the
            # system resolver, and on hosts with acceptDns = true that resolver
            # is MagicDNS, which only speaks A/AAAA and answers NOTIMP to
            # everything else. An explicit resolver bypasses it for ACME only.
            dnsResolver = "1.1.1.1:53";
          };
        };

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
