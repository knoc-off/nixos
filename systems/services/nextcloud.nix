{
  pkgs,
  config,
  ...
}: {

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

  services.nginx.virtualHosts.${config.services.nextcloud.hostName} = {
    forceSSL = true;
    enableACME = true;
  };
}
