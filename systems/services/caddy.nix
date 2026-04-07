{config, ...}: {
  sops.secrets."services/caddy/env" = {
    owner = "caddy";
    group = "caddy";
    mode = "0400";
    # Caddy loads this as a systemd EnvironmentFile and expands {$VAR}
    # placeholders in the generated Caddyfile at startup.
    restartUnits = ["caddy.service"];
  };

  services.caddy = {
    enable = true;
    email = "acme@niko.ink";

    # Sops-managed env file supplies API basic-auth user + bcrypt hash.
    environmentFile = config.sops.secrets."services/caddy/env".path;

    # Caddy handles ACME automatically via HTTP-01 for public-facing servers.
    # No security.acme or DNS provider config needed.

    logFormat = ''
      output file /var/log/caddy/access.log {
        roll_size 50MiB
        roll_keep 5
      }
      format json
    '';

    # Shared snippets. Each service imports the ones it needs.
    extraConfig = ''
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

      (authelia) {
        forward_auth localhost:9091 {
          uri /api/authz/forward-auth?authelia_url=https://auth.niko.ink/
          copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
        }
      }

      (api-basic-auth) {
        basicauth {
          {$API_AUTH_USER} {$API_AUTH_HASH}
        }
      }
    '';

    virtualHosts."niko.ink".extraConfig = ''
      import security-headers
      reverse_proxy localhost:3000
    '';

    virtualHosts."auth.niko.ink".extraConfig = ''
      import security-headers
      reverse_proxy localhost:9091
    '';

    # Abort connections to unknown hostnames / bare IP
    virtualHosts.":443".extraConfig = ''
      tls internal
      abort
    '';
    virtualHosts."http://".extraConfig = ''
      abort
    '';
  };

  # Group-readable logs so CrowdSec can parse them via SupplementaryGroups
  systemd.services.caddy.serviceConfig.UMask = "0027";
  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0750 caddy caddy -"
  ];
}
