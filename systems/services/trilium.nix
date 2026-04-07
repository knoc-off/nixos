{...}: {
  services.trilium-server.enable = true;

  services.caddy.virtualHosts."notes.niko.ink".extraConfig = ''
    import security-headers
    import authelia
    reverse_proxy localhost:8080
  '';

  # Trilium's own ETAPI token auth still applies behind this.
  services.caddy.virtualHosts."notes.api.niko.ink".extraConfig = ''
    import security-headers
    import api-basic-auth
    reverse_proxy localhost:8080
  '';
}
