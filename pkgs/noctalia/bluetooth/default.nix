{
  pkgs,
  lib,
  ...
}: let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
  pkgs.stdenv.mkDerivation {
    pname = "noctalia-bluetooth-plugin";
    version = manifest.version;

    src = ./.;

    installPhase = ''
      mkdir -p $out/bluetooth
      cp -r $src/* $out/bluetooth/
    '';
  }

