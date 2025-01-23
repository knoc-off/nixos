{ pkgs ? import <nixpkgs> { }
, fonts ? []
, templatePatterns ? [ "templates/*.html" "templates/**/*.html" ]
, isDevelopment ? false
, projectRoot ? ./. }:

let
  configData = {
    icon_sets = map (font: {
      inherit (font) name prefix;
      font = {
        file_path = font.file;
        format = font.format;
      };
      path = "data/${builtins.baseNameOf font.file}.json";
    }) fonts;

    template_patterns = templatePatterns;
    output_css_path = "static/css/icons.css";
  };

  configJson = pkgs.writeTextFile {
    name = "icon-config.json";
    text = builtins.toJSON configData;
  };

  combinedScript = pkgs.writeTextFile {
    name = "process-icons.py";
    text = ''
      import json
      import glob
      import re
      import shutil
      from pathlib import Path
      import sys
      from fontTools.ttLib import TTFont
      from fontTools.subset import Subsetter, Options

      def extract_glyph_mapping(font_path, prefix=""):
          font = TTFont(font_path)
          glyph_map = {}

          for cmap in font["cmap"].tables:
              if cmap.isUnicode():
                  for codepoint, glyphname in cmap.cmap.items():
                      if glyphname not in [".notdef", ".null", "nonmarkingreturn"]:
                          glyph_map[f"{prefix}{glyphname}"] = f"{codepoint:04x}"

          return glyph_map

      def scan_templates(template_patterns, prefix):
          used_icons = set()
          pattern = f"{prefix}([a-zA-Z0-9-_]+)"
          print(f"\nScanning for pattern: {pattern}")

          for template_pattern in template_patterns:
              print(f"Looking in: {template_pattern}")
              try:
                  for template_file in glob.glob(template_pattern, recursive=True):
                      try:
                          with open(template_file, "r") as f:
                              content = f.read()
                              matches = re.findall(pattern, content)
                              if matches:
                                  print(f"Found in {template_file}: {matches}")
                                  # Add the full icon name back (prefix + match)
                                  used_icons.update(f"{prefix}{match}" for match in matches)
                      except IOError as e:
                          print(f"Warning: Could not read {template_file}: {e}")
              except Exception as e:
                  print(f"Warning: Error processing pattern {template_pattern}: {e}")

          print(f"Total icons found: {used_icons}")
          return used_icons

      def prune_font(input_font_path, icons_to_keep, output_path):
          font = TTFont(input_font_path)
          options = Options()
          options.layout_features = "*"
          subsetter = Subsetter(options=options)
          subsetter.populate(glyphs=icons_to_keep)
          subsetter.subset(font)
          font.save(output_path)
          font.close()

      def write_debug_info(output_base, template_patterns, icon_sets, used_icons_by_font):
          debug_dir = output_base / "debug"
          debug_dir.mkdir(exist_ok=True)

          # Write scan summary
          with open(debug_dir / "icon-scan-summary.txt", "w") as f:
              f.write("Icon Scanner Debug Information\n")
              f.write("============================\n\n")

              f.write("Template Patterns Scanned:\n")
              for pattern in template_patterns:
                  f.write(f"- {pattern}\n")

              f.write("\nFiles Scanned:\n")
              for pattern in template_patterns:
                  f.write(f"\nPattern: {pattern}\n")
                  for file in glob.glob(pattern, recursive=True):
                      f.write(f"- {file}\n")

              f.write("\nIcons Found By Font:\n")
              for font_name, icons in used_icons_by_font.items():
                  f.write(f"\n{font_name}:\n")
                  for icon in sorted(icons):
                      f.write(f"- {icon}\n")

      def generate_css(icon_set, glyph_map, used_icons):
          css = f"""/* Generated {icon_set["name"]} CSS */
      @font-face {{
          font-family: '{icon_set["name"]}';
          font-style: normal;
          font-weight: 400;
          src: url("../fonts/{Path(icon_set["font"]["file_path"]).name}") format("{icon_set["font"]["format"]}");
      }}

      /* Base icon styles for {icon_set["name"]} */
      .{icon_set["name"]} {{
          font-family: '{icon_set["name"]}';
          font-weight: 900;
          font-style: normal;
          font-size: 24px;
          line-height: 1;
          letter-spacing: normal;
          text-transform: none;
          display: inline-block;
          white-space: nowrap;
          word-wrap: normal;
          direction: ltr;
          -webkit-font-smoothing: antialiased;
      }}

      /* Icon-specific styles */
      """
          # Collect all icon selectors
          icon_selectors = []
          icon_contents = []

          print(f"\nProcessing icons for {icon_set['name']}:")
          print(f"Available mappings: {list(glyph_map.keys())[:5]}...")
          print(f"Used icons: {used_icons}")

          for icon_name in used_icons:
              if icon_name in glyph_map:
                  selector = f".{icon_name}"
                  icon_selectors.append(selector)
                  icon_contents.append(f"{selector}::before {{ content: \"\\{glyph_map[icon_name]}\"; }}")
                  print(f"Added icon: {icon_name} -> \\{glyph_map[icon_name]}")
              else:
                  print(f"Warning: Icon '{icon_name}' not found in glyph map")

          if icon_selectors:
              # Add shared properties for all icons
              css += f"{', '.join(icon_selectors)} {{\n"
              css += f"    font-family: '{icon_set["name"]}';\n"
              css += "}\n\n"

              # Add individual content properties
              css += '\n'.join(icon_contents)

          return css

      def main():
          try:
              with open(sys.argv[1], 'r') as f:
                  config = json.load(f)
          except Exception as e:
              print(f"Error reading config file: {e}")
              sys.exit(1)

          output_base = Path(sys.argv[2])
          is_dev = sys.argv[3].lower() == "true"

          fonts_dir = output_base / "share/fonts"
          data_dir = output_base / "share/data"
          css_dir = output_base / "share/css"
          debug_dir = output_base / "debug"

          for dir in [fonts_dir, data_dir, css_dir, debug_dir]:
              dir.mkdir(parents=True, exist_ok=True)

          complete_css = ""
          used_icons_by_font = {}

          for icon_set in config["icon_sets"]:
              font_path = icon_set["font"]["file_path"]
              prefix = icon_set["prefix"]
              font_name = Path(font_path).name

              glyph_map = extract_glyph_mapping(font_path, prefix)
              mapping_file = data_dir / f"{font_name}.json"
              with open(mapping_file, 'w') as f:
                  json.dump(glyph_map, f, indent=2)

              shutil.copy2(font_path, fonts_dir / Path(font_path).name)

              if is_dev:
                  used_icons = set(glyph_map.keys())
              else:
                  used_icons = scan_templates(config["template_patterns"], prefix)

              used_icons_by_font[font_name] = list(used_icons)
              complete_css += generate_css(icon_set, glyph_map, used_icons)
              complete_css += "\n\n"

          with open(css_dir / "icons.css", 'w') as f:
              f.write(complete_css)

          write_debug_info(output_base, config["template_patterns"],
                          config["icon_sets"], used_icons_by_font)

      if __name__ == "__main__":
          main()
    '';
  };

in
pkgs.stdenv.mkDerivation {
  name = "icon-processor";

  dontUnpack = true;

  buildInputs = [
    pkgs.python3
    pkgs.python3Packages.fonttools
    pkgs.python3Packages.brotli
  ];

  buildPhase = ''
    # Copy template files from source
    cp -r ${projectRoot}/* ./

    # Run processing script with the local template directory
    python3 ${combinedScript} ${configJson} $out ${if isDevelopment then "true" else "false"}
  '';

  installPhase = "true";
}
