{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "noctalia-screen-shot";
  version = "1.0.0";
  src = ./.;
  installPhase = ''
    mkdir -p $out/screen-shot
    cp -r * $out/screen-shot
  '';
}
