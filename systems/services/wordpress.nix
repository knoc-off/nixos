{ ... }: let
  domain = "niko.ink";
in {


  imports = [
    #./wordpress-oci.nix
    ./docker-compose.nix
  ];


  services.nginx.virtualHosts.${domain} = {
    forceSSL = true;
    enableACME = true;
    locations."/" = {
      proxyPass = "http://127.0.0.1:8000";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
      '';
    };
  };


  #virtualisation.docker.enable = true;


#  services.phpfpm.pools."wordpress-${domain}".phpOptions = ''
#    upload_max_filesize=1G
#    post_max_size=1G
#  '';
#
#  services.wordpress = {
#    webserver = "nginx";
#    sites.${domain} = {
#    };
#  };
#
#  services.nginx.virtualHosts.${domain} = {
#    forceSSL = true;
#    enableACME = true;
#  };





}
