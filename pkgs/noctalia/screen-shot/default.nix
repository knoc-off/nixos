{pkgs, ...}:
let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
pkgs.stdenv.mkDerivation {
  pname = "noctalia-screen-shot";
  version = manifest.version;
  src = ./.;
  installPhase = ''
    mkdir -p $out/screen-shot
    cp -r * $out/screen-shot
  '';
}
