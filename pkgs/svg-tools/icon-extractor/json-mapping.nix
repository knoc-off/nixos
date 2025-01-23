{ pkgs ? import <nixpkgs> { }
, package
, fontPath
, prefix ? ""
}:

let
  extractScript = pkgs.writeTextFile {
    name = "extract_glyphs.py";
    text = ''
      import sys
      import json
      import re
      from fontTools.ttLib import TTFont

      if len(sys.argv) < 2:
          print("Usage: extract_glyphs.py <font_path> [prefix]")
          sys.exit(1)

      font_path = sys.argv[1]
      prefix = ""
      if len(sys.argv) > 2 and sys.argv[2] != "no-prefix":
          prefix = f"{sys.argv[2]}_"

      font = TTFont(font_path)
      glyph_map = {}

      for cmap in font["cmap"].tables:
          if cmap.isUnicode():
              for codepoint, glyphname in cmap.cmap.items():
                  if glyphname not in [".notdef", ".null", "nonmarkingreturn"]:
                      glyph_map[f"{prefix}{glyphname}"] = f"{codepoint:04x}"

      with open("glyph_unicode_map.json", "w", encoding="utf-8") as out_file:
          json.dump(glyph_map, out_file, indent=2)

      print("glyph_unicode_map.json created successfully.")
    '';
  };
in
pkgs.stdenv.mkDerivation {
  name = "icon-unicode-mapper";
  src = null;

  buildInputs = [
    pkgs.python3
    pkgs.python3Packages.fonttools
    pkgs.python3Packages.brotli  # Required by fonttools
  ];

  unpackPhase = "true";

  buildPhase = ''
    echo "Full package path: ${package}"
    echo "Attempting to access: ${package}${fontPath}"
    python3 ${extractScript} "${package}${fontPath}" "${prefix}"
  '';

  installPhase = ''
    mkdir -p $out/share/
    cp glyph_unicode_map.json $out/share/
  '';

  meta = with pkgs.lib; {
    description = "Generate JSON mapping of glyph names to unicode values from a font file";
    license = licenses.mit;
    maintainers = [ knoff ];
    platforms = platforms.all;
  };
}
