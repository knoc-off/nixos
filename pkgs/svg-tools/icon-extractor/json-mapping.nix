{ pkgs ? import <nixpkgs> { }
, package
, fontPath
, prefix ? ""
}:

let
  extractScript = pkgs.writeTextFile {
    name = "extract_glyphs.py";
    text = ''
      import fontforge
      import os
      import json
      import re
      import sys

      def sanitize_filename(name):
          return re.sub(r'[<>:"/\\|?*]', '_', name)

      if len(sys.argv) < 2:
          print("Usage: python extract_glyphs.py <font_path> [prefix]")
          print("Example: python extract_glyphs.py ./my-font.otf mi")
          sys.exit(1)

      font_path = sys.argv[1]
      print(f"Attempting to open font file at: {os.path.abspath(font_path)}")

      if not os.path.exists(font_path):
          print(f"ERROR: Font file does not exist at path: {font_path}")
          sys.exit(1)

      prefix = ""

      if len(sys.argv) > 2:
          prefix = sys.argv[2]
          if prefix != "":
              prefix = f"{prefix}_"

      try:
          font = fontforge.open(font_path)
      except Exception as e:
          print(f"Error opening font file: {e}")
          sys.exit(1)

      glyph_map = {}

      for glyph in font.glyphs():
          if glyph.glyphname and glyph.unicode != -1:
              key_name = f"{prefix}{glyph.glyphname}" if prefix else glyph.glyphname
              hex_code = f"{glyph.unicode:04x}"
              glyph_map[key_name] = hex_code

      # Write to JSON file
      with open('glyph_unicode_map.json', 'w', encoding='utf-8') as jsonfile:
          json.dump(glyph_map, jsonfile, indent=2)

      print("JSON mapping file has been created as glyph_unicode_map.json")
    '';
  };
in
pkgs.stdenv.mkDerivation {
  name = "icon-unicode-mapper";
  src = null;

  buildInputs = [
    pkgs.fontforge
    pkgs.python3
    pkgs.python3Packages.setuptools  # Added for pkg_resources
  ];

  unpackPhase = "true";

  buildPhase = ''
    echo "Full package path: ${package}"
    echo "Attempting to access: ${package}${fontPath}"
    fontforge -script ${extractScript} "${package}${fontPath}" "${prefix}"
  '';

  installPhase = ''
    mkdir -p $out/share/
    cp glyph_unicode_map.json $out/share/
  '';

  meta = with pkgs.lib; {
    description = "Generate JSON mapping of glyph names to unicode values from a font file";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.all;
  };
}
