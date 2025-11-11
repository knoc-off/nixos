{config, ...}: {
  # Enable Podman
  virtualisation = {
    podman = {
      enable = true;
      autoPrune.enable = true;
      dockerCompat = true;
      defaultNetwork.settings = {
        dns_enabled = true;
      };
    };

    # Set OCI containers backend to Podman
    oci-containers.backend = "podman";

    # Define the OCI container for KitchenOwl
    oci-containers.containers = {
      kitchenowl = {
        image = "tombursch/kitchenowl@sha256:9d5e4402c2abc734e1536586caa103840a7ebe961fdce1570e31b956abeba70b";
        ports = ["3043:8080"];
        environmentFiles = [
          config.sops.secrets."services/kitchenowl/jwt-secret".path
        ];
        volumes = [
          "/var/lib/kitchenowl:/data"
        ];
      };
    };
  };

  # Ensure the data directory exists and has correct permissions
  systemd.tmpfiles.rules = [
    "d /var/lib/kitchenowl 0755 root root -"
  ];

  services.nginx = {
    # need to find a way to easily configure to domain name, not hard code it
    virtualHosts."kitchenowl.niko.ink" = {
      forceSSL = true;
      enableACME = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:3043";
        proxyWebsockets = true; # Enable WebSocket support if needed

        extraConfig = ''
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "upgrade";
        '';
      };
    };
  };

  # Open firewall port
  #networking.firewall.allowedTCPPorts = [ 3043 ];
}
