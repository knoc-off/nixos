{ inputs, pkgs, ... }:
let
  upkgs = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = {
      allowUnfree = true;
    };
  };
in
{
  services.trilium-server = {
    # Flaky. waiting for upstream fix
    enable = false;
    package = upkgs.trilium-server;
  };

  services.caddy.virtualHosts."notes.niko.ink" = {
    useACMEHost = "niko.ink";
    extraConfig = ''
      import security-headers
      import auth-public
      reverse_proxy localhost:8080
    '';
  };
}
