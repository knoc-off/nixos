{config, ...}: {
  virtualisation = {
    podman = {
      enable = true;
      autoPrune.enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    oci-containers.backend = "podman";
    oci-containers.containers.kitchenowl = {
      image = "tombursch/kitchenowl@sha256:9d5e4402c2abc734e1536586caa103840a7ebe961fdce1570e31b956abeba70b";
      # Localhost-only -- Caddy handles external traffic
      ports = ["127.0.0.1:3043:8080"];
      environmentFiles = [
        config.sops.secrets."services/kitchenowl/jwt-secret".path
      ];
      volumes = [
        "/var/lib/kitchenowl:/data"
      ];
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/kitchenowl 0755 root root -"
  ];

  services.caddy.virtualHosts."kitchenowl.niko.ink".extraConfig = ''
    import security-headers
    import auth-public
    reverse_proxy localhost:3043
  '';
}
