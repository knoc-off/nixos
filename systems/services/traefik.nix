{ config, lib, pkgs, ... }:

{
  # Enable the Traefik service
  services.traefik = {
    enable = true;

    # Define secret credentials for Namecheap using the encrypted .env file
    environmentFiles = [
      # The sops file looks like:
      #   namecheap-user-env: NAMECHEAP_API_USER=<user>
      #   namecheap-key-env: NAMECHEAP_API_KEY=<key>
      "${config.sops.secrets."services/acme/namecheap-user-env".path}"
      "${config.sops.secrets."services/acme/namecheap-key-env".path}"
    ];

    # Define static configuration options
    staticConfigOptions = {

      global = {
        checkNewVersion = false;
        sendAnonymousUsage = false;
      };
      entryPoints = {
        web = {
          address = ":80";
        };
        websecure = {
          address = ":443";
        };
      };



      certificatesResolvers = {
        myresolver = {
          acme = {
            email = "acme@niko.ink";
            storage = "/var/lib/traefik/acme.json";
            dnsChallenge = {
              provider = "namecheap";
              delayBeforeCheck = 0;
            };
          };
        };
      };
    };

    # Define dynamic configuration options
    dynamicConfigOptions = {


      http = {
        routers = {
          example = {
            rule = "Host(`kobbl.co`)";
            entryPoints = [ "websecure" ];  # Use websecure for HTTPS
            service = "example";
            tls = {
              certResolver = "myresolver";
            };
          };
        };
        services = {
          example = {
            loadBalancer = {
              servers = [
                { url = "http://127.0.0.1:8080"; }
              ];
            };
          };
        };
      };
    };
  };
}
