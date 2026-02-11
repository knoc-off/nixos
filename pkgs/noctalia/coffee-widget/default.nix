{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "noctalia-coffee-widget";
  version = "1.0.0";
  src = ./.;
  installPhase = ''
    mkdir -p $out/coffee
    cp -r * $out/coffee
  '';
}
