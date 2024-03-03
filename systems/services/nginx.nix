{
  pkgs,
  config,
  ...
}: {
  sops.secrets."services/acme/namecheap-user" = {};
  sops.secrets."services/acme/namecheap-key" = {};

  security = {
    acme = {
      defaults = {
        dnsProvider = "namecheap";
        email = "acme@niko.ink";
        credentialFiles = {
          "NAMECHEAP_API_USER_FILE" = config.sops.secrets."services/acme/namecheap-user".path;
          "NAMECHEAP_API_KEY_FILE" = config.sops.secrets."services/acme/namecheap-key".path;
        };
      };
      acceptTerms = true;
    };
  };

  services.nginx.virtualHosts.${config.services.nextcloud.hostName} = {
    forceSSL = true;
    enableACME = true;
  };

  services.nginx.virtualHosts."niko.ink" = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:3000";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
      '';
    };
  };
}
