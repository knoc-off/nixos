{ pkgs ? import <nixpkgs> { }, fontPath, }:
pkgs.stdenv.mkDerivation {
  name = "extract-icons-svg";
  src = null;

  buildInputs = [ pkgs.fontforge ];

  # Disable the unpack phase
  unpackPhase = "true";

  buildPhase = ''
        mkdir -p svg_files
        fontforge -lang=py -c '

    otfinfo --unicode ${fontPath}
  '';

  installPhase = ''
    mkdir -p $out/chart
    cp  $out/svg_files/
  '';
}
