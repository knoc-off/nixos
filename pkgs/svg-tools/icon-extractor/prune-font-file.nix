{ pkgs ? import <nixpkgs> { }
, package
, fontPath
, iconList
}:

let
  pruneScript = pkgs.writeTextFile {
    name = "prune_font.py";
    text = ''
      import fontforge
      import os
      import json
      import sys
      import re

      def sanitize_filename(name):
          return re.sub(r'[<>:"/\\|?*]', '_', name)

      def get_output_filename(input_path):
          base = os.path.basename(input_path)
          name, ext = os.path.splitext(base)
          return f"{name}-pruned{ext}"

      if len(sys.argv) < 4:
          print("Usage: python prune_font.py <input_font_path> <icons_json_path> <output_font_path>")
          print("Example: python prune_font.py ./input.otf ./used_icons.json ./pruned.otf")
          sys.exit(1)

      input_font_path = sys.argv[1]
      icons_json_path = sys.argv[2]
      output_font_path = sys.argv[3]

      print(f"Input font path: {os.path.abspath(input_font_path)}")
      print(f"Icons JSON path: {os.path.abspath(icons_json_path)}")
      print(f"Output path: {os.path.abspath(output_font_path)}")

      # Load the list of icons to keep
      try:
          with open(icons_json_path, 'r') as f:
              icons_to_keep = json.load(f)
      except Exception as e:
          print(f"Error reading icons JSON file: {e}")
          sys.exit(1)

      # Convert icons_to_keep values to a set of names
      if isinstance(icons_to_keep, dict):
          icon_names = set(icons_to_keep.keys())
      else:
          icon_names = set(icons_to_keep)

      # Open the font
      try:
          font = fontforge.open(input_font_path)
      except Exception as e:
          print(f"Error opening font file: {e}")
          sys.exit(1)

      # Keep track of removed glyphs
      removed_count = 0
      kept_count = 0

      # Iterate through glyphs and remove unwanted ones
      for glyph in list(font.glyphs()):
          if glyph.glyphname:
              if glyph.glyphname not in icon_names:
                  font.removeGlyph(glyph)
                  removed_count += 1
              else:
                  kept_count += 1

      # Generate the new font file
      try:
          font.generate(output_font_path)
          print(f"Successfully created pruned font at: {output_font_path}")
          print(f"Kept {kept_count} glyphs, removed {removed_count} glyphs")
      except Exception as e:
          print(f"Error generating pruned font: {e}")
          sys.exit(1)

      font.close()
    '';
  };

  # Convert the icon list to a JSON file
  iconListJson = pkgs.writeTextFile {
    name = "icon-list.json";
    text = builtins.toJSON iconList;
  };

  # Extract the basename and extension from the input font path
  baseName = builtins.baseNameOf fontPath;
  nameWithoutExt = builtins.head (builtins.split "\\." baseName);
  extension = builtins.elemAt (builtins.split "\\." baseName) 2;
  outputName = "${nameWithoutExt}-pruned.${extension}";
in
pkgs.stdenv.mkDerivation {
  name = "font-pruner";
  src = null;

  buildInputs = [
    pkgs.fontforge
    pkgs.python3
    pkgs.python3Packages.setuptools
  ];

  unpackPhase = "true";

  buildPhase = ''
    echo "Processing font: ${package}${fontPath}"
    echo "Using icon list from: ${iconListJson}"
    echo "Output will be saved as: ${outputName}"
    fontforge -script ${pruneScript} "${package}${fontPath}" "${iconListJson}" "${outputName}"
  '';

  installPhase = ''
    mkdir -p $out
    cp ${outputName} $out/
  '';

  meta = with pkgs.lib; {
    description = "Create a pruned font containing only specified glyphs";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.all;
  };
}
