{...}: {
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
        image = "tombursch/kitchenowl@sha256:5e8462c9be9b31aa9b829275a25ea17f2e5c58be891013a409355ebbac89c6d8";
        ports = ["3043:8080"];
        environment = {
          JWT_SECRET_KEY = "PLEASE_CHANGE_ME";
        };
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
      };
    };
  };

  # Open firewall port
  #networking.firewall.allowedTCPPorts = [ 3043 ];
}
