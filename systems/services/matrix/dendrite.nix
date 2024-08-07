{ config, pkgs, ... }:
{
  # Configure SOPS for secret management
  sops = {
    secrets = {
        "services/dendrite/environment" = {};
        "services/dendrite/private-key" = {};
    };
  };

  # Enable the Dendrite service
  services.dendrite = {
    enable = true;
    environmentFile = "${config.sops.secrets."services/dendrite/environment".path}";
    settings = {
      global = {
        server_name = "niko.ink";
        private_key = "${config.sops.secrets."services/dendrite/private-key".path}";
      };
      client_api = {
        registration_disabled = false;
        registration_shared_secret = "$REGISTRATION_SHARED_SECRET";
        enable_registration_captcha = false;
      };
    };
  };

  # Firewall configuration
  #networking.firewall = {
  #  allowedTCPPorts = [ 80 443 8448 ];
  #};

  # NGINX reverse proxy configuration (optional, but recommended)
  #services.nginx = {
  #  enable = true;
  #  recommendedProxySettings = true;
  #  recommendedTlsSettings = true;
  #  virtualHosts."example.com" = {
  #    forceSSL = true;
  #    enableACME = true;
  #    locations."/_matrix" = {
  #      proxyPass = "http://localhost:8008";
  #    };
  #  };
  #};

  # Add any other system configurations here
}
