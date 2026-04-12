{upkgs, ...}: {
  services.trilium-server = {
    enable = true;
    package = upkgs.trilium-server;
  };

  services.caddy.virtualHosts."notes.niko.ink".extraConfig = ''
    import security-headers
    import auth-public
    reverse_proxy localhost:8080
  '';
}
