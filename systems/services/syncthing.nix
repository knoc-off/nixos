{ config, pkgs, ... }:
{
  services.syncthing.relay = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 22067;
    statusListenAddress = "0.0.0.0";
    statusPort = 22070;
    pools = null;  # Use default global pool
    providedBy = "oink-relay";
    globalRateBps = null;  # No global rate limit
    perSessionRateBps = null;  # No per session rate limit
    extraOptions = [];
  };

  services.nginx = {
    virtualHosts."relay.niko.ink" = {
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:22067";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
        "/status" = {
          proxyPass = "http://127.0.0.1:22070";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          '';
        };
      };
    };
  };
}
