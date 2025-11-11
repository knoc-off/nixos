{
  pkgs,
  config,
  inputs,
  self,
  ...
}: let
  system = "x86_64-linux";
  baseDir = "niko.ink";
in {
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

  services.nginx.enable = true;

  # Default catch-all for unmatched requests
  services.nginx.virtualHosts."_" = {
    default = true;
    rejectSSL = true;
    locations."/".return = "444";
  };

  #services.nginx.virtualHosts."niko.ink" = {
  #  forceSSL = true;
  #  enableACME = true;
  #  locations = {
  #    "/" = {
  #      root = "${self.packages.${pkgs.system}.website.portfolio}/lib";
  #      tryFiles = "$uri $uri/ /index.html";
  #    };
  #  };
  #};

  # passing proxy, port
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

  #  # Eileen Domain:
  #  security.acme.certs."agedesign.org" = {
  #    credentialsFile = {
  #          "NAMECHEAP_API_USER_FILE" = config.sops.secrets."services/acme/namecheap-user2".path;
  #          "NAMECHEAP_API_KEY_FILE" = config.sops.secrets."services/acme/namecheap-key2".path;
  #    };
  #  };
}
