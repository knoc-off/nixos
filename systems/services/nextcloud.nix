{
  pkgs,
  config,
  ...
}: {
  #sops.secrets.example-key = {};
  sops.secrets."services/nextcloud/admin-pass" = {};
  sops.secrets."services/nextcloud/admin-pass".owner = config.users.users.nextcloud.name;

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud28;
    hostName = "nextcloud.niko.ink";
    https = true;
    config.adminpassFile = config.sops.secrets."services/nextcloud/admin-pass".path;
    configureRedis = true;
    maxUploadSize = "1G";

    extraAppsEnable = true;
    extraApps = {
      inherit (config.services.nextcloud.package.packages.apps) contacts calendar tasks notes mail bookmarks music qownnotesapi deck phonetrack;
    };
  };

  sops.secrets."services/acme/namecheap-user" = {};
  sops.secrets."services/acme/namecheap-key" = {};

  security.acme.defaults.dnsProvider = "namecheap";
  security.acme.defaults.email = "acme@niko.ink";
  security.acme.defaults.credentialFiles = {
    "NAMECHEAP_API_USER_FILE" = config.sops.secrets."services/acme/namecheap-user".path;
    "NAMECHEAP_API_KEY_FILE" = config.sops.secrets."services/acme/namecheap-key".path;
  };
  security.acme.acceptTerms = true;

  services.nginx.virtualHosts.${config.services.nextcloud.hostName} = {
    forceSSL = true;
    enableACME = true;
  };
}
