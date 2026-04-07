{
  pkgs,
  config,
  inputs,
  self,
  ...
}: let
  # Applied per-vhost so nginx add_header inheritance doesn't silently
  # drop them when a server block adds its own headers.
  securityHeaders = ''
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
  '';
in {
  sops.secrets."services/acme/namecheap-user" = {};
  sops.secrets."services/acme/namecheap-key" = {};

  security.acme = {
    acceptTerms = true;
    defaults = {
      dnsProvider = "namecheap";
      email = "acme@niko.ink";
      credentialFiles = {
        "NAMECHEAP_API_USER_FILE" = config.sops.secrets."services/acme/namecheap-user".path;
        "NAMECHEAP_API_KEY_FILE" = config.sops.secrets."services/acme/namecheap-key".path;
      };
    };
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    serverTokens = false;

    # Zone definitions must live at http level; commonHttpConfig is placed
    # before server blocks so zones are available to all vhosts.
    commonHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
      limit_conn_zone $binary_remote_addr zone=addr:10m;
    '';

    # Drop connections to unknown hostnames / bare IP
    virtualHosts."_" = {
      default = true;
      rejectSSL = true;
      locations."/".return = "444";
    };

    virtualHosts."niko.ink" = {
      forceSSL = true;
      enableACME = true;
      extraConfig = securityHeaders;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        '';
      };
    };
  };
}
