{ pkgs, ... }:
pkgs.stdenv.mkDerivation {
  pname = "noctalia-audio-recorder";
  version = "1.0.9";
  src = ./.;
  installPhase = ''
    mkdir -p $out/audio-recorder
    cp -r * $out/audio-recorder
  '';
}
