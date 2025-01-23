{ pkgs ? import <nixpkgs> { }
, package
, fontPath
, iconList
}:

let
  pruneScript = pkgs.writeTextFile {
    name = "prune_font.py";
    text = ''
      import sys
      import json
      from fontTools.ttLib import TTFont
      from fontTools.subset import Subsetter, Options

      if len(sys.argv) < 4:
          print("Usage: python prune_font.py <input_font_path> <icons_json_path> <output_font_path>")
          print("Example: python prune_font.py ./input.ttf ./used_icons.json ./pruned.ttf")
          sys.exit(1)

      input_font_path = sys.argv[1]
      icons_json_path = sys.argv[2]
      output_font_path = sys.argv[3]

      # Load the list of icons to keep
      try:
          with open(icons_json_path, "r") as f:
              icons_to_keep = json.load(f)
      except Exception as e:
          print(f"Error reading icons JSON file: {e}")
          sys.exit(1)

      # Convert the JSON into a set of glyph names
      if isinstance(icons_to_keep, dict):
          # e.g. {"icon_name": "e92c", "icon_name2": "eabc"}
          icon_names = set(icons_to_keep.keys())
      elif isinstance(icons_to_keep, list):
          # e.g. ["icon_name", "icon_name2"]
          icon_names = set(icons_to_keep)
      else:
          print("JSON structure not recognized. Must be a dict or list.")
          sys.exit(1)

      # Open the font
      try:
          font = TTFont(input_font_path)
      except Exception as e:
          print(f"Error opening font file: {e}")
          sys.exit(1)

      options = Options()
      options.layout_features = "*"
      subsetter = Subsetter(options=options)
      # Provide the glyph names to keep
      subsetter.populate(glyphs=icon_names)

      try:
          subsetter.subset(font)
          font.save(output_font_path)
          print(f"Successfully created pruned font at: {output_font_path}")
      except Exception as e:
          print(f"Error generating pruned font: {e}")
          sys.exit(1)
      finally:
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
    pkgs.python3
    pkgs.python3Packages.fonttools
    pkgs.python3Packages.brotli  # Required by fonttools
  ];

  unpackPhase = "true";

  buildPhase = ''
    echo "Processing font: ${package}${fontPath}"
    echo "Using icon list from: ${iconListJson}"
    echo "Output will be saved as: ${outputName}"
    python3 ${pruneScript} "${package}${fontPath}" "${iconListJson}" "${outputName}"
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
