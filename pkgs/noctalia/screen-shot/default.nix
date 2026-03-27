{lib, stdenv}: let
  manifest = builtins.fromJSON (builtins.readFile ./manifest.json);
in
  stdenv.mkDerivation {
    pname = "noctalia-screen-shot";
    version = manifest.version;
    src = ./.;
    installPhase = ''
      mkdir -p $out/screen-shot
      cp -r * $out/screen-shot
    '';
  }
