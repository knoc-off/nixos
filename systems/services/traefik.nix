{ config, lib, pkgs, ... }:

{
  # Enable the Traefik service
  services.traefik = {
    enable = true;

    # Define secret credentials for Namecheap using the encrypted .env file
    environmentFiles = [
      #"${config.sops.secrets."services/acme/envfile".path}"
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
        minecraft = {
          address = ":25565";
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




      tcp = {
        routers = {
          minecraft = {
            rule = "HostSNI(`one.kobbl.co`)";
            entryPoints = [ "minecraft" ];
            service = "minecraft";
            tls = {
              certResolver = "myresolver";
              domains = [
                { main = "*.kobbl.co"; sans = [ "kobbl.co" ]; }
              ];
            };
          };
          minecraftTwo = {
            rule = "HostSNI(`two.kobbl.co`)";
            entryPoints = [ "minecraft" ];
            service = "minecraftTwo";
            tls = {
              certResolver = "myresolver";
              domains = [
                { main = "*.kobbl.co"; sans = [ "kobbl.co" ]; }
              ];
            };
          };
        };
        services = {
          minecraft = {
            loadBalancer = {
              servers = [
                { address = "127.0.0.1:25500"; }
              ];
            };
          };
          minecraftTwo = {
            loadBalancer = {
              servers = [
                { address = "127.0.0.1:25501"; }
              ];
            };
          };
        };
      };








    };
  };

  # Allow HTTP and Minecraft traffic in the firewall
  networking.firewall.allowedTCPPorts = [ 80 25565 ];
}
