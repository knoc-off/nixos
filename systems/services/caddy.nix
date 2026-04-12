{
  self,
  config,
  lib,
  ...
}: let
  trustedIps = lib.concatStringsSep " " config.services.wireguard-network.trustedSubnets;
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

    extraConfig = ''
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

    virtualHosts.":443".extraConfig = ''
      tls internal
      abort
    '';
    virtualHosts."http://".extraConfig = ''
      abort
    '';
  };

  # 0027 so CrowdSec (supplementary group) can read logs
  systemd.services.caddy.serviceConfig.UMask = "0027";
  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0750 caddy caddy -"
  ];
}
