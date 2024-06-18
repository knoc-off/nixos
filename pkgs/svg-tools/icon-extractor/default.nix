{ pkgs ? import <nixpkgs> {}, iconsPackage, fontPath }:

pkgs.stdenv.mkDerivation {
  name = "extract-icons-svg";
  src = null;

  buildInputs = [
    iconsPackage
    pkgs.fontforge
  ];

  # Disable the unpack phase
  unpackPhase = "true";

  buildPhase = ''
    mkdir -p svg_files
    fontforge -lang=py -c '
import os, fontforge
font = fontforge.open("${iconsPackage}/${fontPath}")
os.makedirs("svg_files", exist_ok=True)
[glyph.export(f"svg_files/{glyph.glyphname}.svg") for glyph in font.glyphs() if glyph.glyphname]'
  '';

  installPhase = ''
    mkdir -p $out/svg_files
    cp -r svg_files/* $out/svg_files/
  '';

  meta = with pkgs.lib; {
    description = "Extract SVG data from a specified icons font package";
    license = licenses.mit;
    maintainers = [ maintainers.yourself ];
    platforms = platforms.all;
  };
}
