{config, lib, ...}: let
  trustedIps = lib.concatStringsSep " " config.services.wireguard-network.trustedSubnets;
in {
  services.caddy = {
    enable = true;
    email = "acme@niko.ink";

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

      (auth) {
        forward_auth localhost:4180 {
          uri /oauth2/auth
          copy_headers X-Auth-Request-User X-Auth-Request-Email

          @unauthorized status 401
          handle_response @unauthorized {
            redir https://auth.niko.ink/oauth2/start?rd=https://{host}{uri}
          }
        }
      }

      (auth-public) {
        @untrusted not remote_ip ${trustedIps} 127.0.0.1
        forward_auth @untrusted localhost:4180 {
          uri /oauth2/auth
          copy_headers X-Auth-Request-User X-Auth-Request-Email

          @unauthorized status 401
          handle_response @unauthorized {
            redir https://auth.niko.ink/oauth2/start?rd=https://{host}{uri}
          }
        }
      }
    '';

    virtualHosts."niko.ink".extraConfig = ''
      import security-headers
      reverse_proxy localhost:3000
    '';

    virtualHosts."auth.niko.ink".extraConfig = ''
      import security-headers
      reverse_proxy localhost:4180
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
