{ pkgs ? import <nixpkgs> { }
, icons ? []
, templatePatterns ? [ "templates/*.html" "templates/**/*.html" ]
, isDevelopment ? false
, projectRoot ? ./. }:

let
  configData = {
    icon_sets = map (icon: {
      inherit (icon) name prefix;
      path = "static/icons/${icon.name}";
      source_path = "${icon.package}${icon.path}";
    }) icons;

    template_patterns = templatePatterns;
    output_css_path = "static/css/svg-icons.css";
  };

  configJson = pkgs.writeTextFile {
    name = "svg-icon-config.json";
    text = builtins.toJSON configData;
  };

  processorScript = pkgs.writeTextFile {
    name = "process-svg-icons.py";
    text = ''
      import json
      import glob
      import re
      import os
      from pathlib import Path
      import sys
      import shutil
      import base64

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
                                  used_icons.update(f"{prefix}{match}" for match in matches)
                      except IOError as e:
                          print(f"Warning: Could not read {template_file}: {e}")
              except Exception as e:
                  print(f"Warning: Error processing pattern {template_pattern}: {e}")

          return used_icons

      def process_svg_files(source_path, target_path):
          svg_files = {}
          for svg_file in glob.glob(f"{source_path}/*.svg"):
              name = Path(svg_file).stem
              # Just store the name, we'll use it to generate the path
              svg_files[name] = name
          return svg_files

      def generate_css(icon_set, svg_data, used_icons):
          css = f"/* Generated {icon_set['name']} SVG CSS */\n"

          for icon_name in used_icons:
              clean_name = icon_name.replace(icon_set["prefix"], "")
              if clean_name in svg_data:
                  selector = f".{icon_name}"
                  # Insert the SVG content directly via CSS content property
                  css += f"{selector} {{\n"
                  css += "    display: inline-block;\n"
                  css += "    width: 1.5rem;\n"  # Default size, can be overridden by Tailwind
                  css += "    height: 1.5rem;\n"
                  css += f"    content: ''';\n"  # Empty content for the pseudo-element
                  css += "}\n\n"

                  # Create a pseudo-element that contains the actual SVG
                  css += f"{selector}::after {{\n"
                  css += "    content: ''';\n"
                  css += "    display: block;\n"
                  css += "    width: 100%;\n"
                  css += "    height: 100%;\n"
                  # Insert actual SVG as background
                  css += f"    background-color: currentColor;\n"
                  css += f"    mask: url('../icons/{icon_set['name']}/{clean_name}.svg') no-repeat center / contain;\n"
                  css += f"    -webkit-mask: url('../icons/{icon_set['name']}/{clean_name}.svg') no-repeat center / contain;\n"
                  css += "}\n\n"

          return css

      def generate_js(icon_set, svg_data, used_icons):
          js = """
      class IconComponent extends HTMLElement {
          static icons = new Map();

          static async loadIcon(name) {
              const response = await fetch(`/icons/${name}.svg`);
              const text = await response.text();
              // Extract SVG content, preserving viewBox and removing hardcoded sizes
              const parser = new DOMParser();
              const doc = parser.parseFromString(text, 'image/svg+xml');
              const svg = doc.querySelector('svg');

              // Remove fixed dimensions but keep viewBox
              svg.removeAttribute('width');
              svg.removeAttribute('height');

              return svg.outerHTML;
          }

          async connectedCallback() {
              const iconClass = Array.from(this.classList).find(c => c.startsWith('tif_'));
              if (!iconClass) return;

              const iconName = iconClass.replace('tif_', ''');

              if (!IconComponent.icons.has(iconName)) {
                  IconComponent.icons.set(
                      iconName,
                      await IconComponent.loadIcon(`tabler-icons-filled/$${iconName}`)
                  );
              }

              const svgContent = IconComponent.icons.get(iconName);

              // Create wrapper to preserve classes
              const wrapper = document.createElement('div');
              wrapper.innerHTML = svgContent;
              const svg = wrapper.firstChild;

              // Copy all classes from the component to the SVG
              svg.classList.add(...this.classList);
              // Remove the icon identifier class from SVG
              svg.classList.remove(iconClass);

              // Add default classes for proper sizing
              svg.classList.add('w-full', 'h-full');

              this.replaceWith(svg);
          }
      }

      customElements.define('icon-component', IconComponent);
      """
          return js

      def write_debug_info(debug_dir, template_patterns, icon_sets, used_icons_by_set):
          with open(debug_dir / "svg-scan-summary.txt", "w") as f:
              f.write("SVG Icon Scanner Debug Information\n")
              f.write("================================\n\n")

              f.write("Template Patterns Scanned:\n")
              for pattern in template_patterns:
                  f.write(f"- {pattern}\n")

              f.write("\nFiles Scanned:\n")
              for pattern in template_patterns:
                  f.write(f"\nPattern: {pattern}\n")
                  for file in glob.glob(pattern, recursive=True):
                      f.write(f"- {file}\n")

              f.write("\nIcons Found By Set:\n")
              for set_name, icons in used_icons_by_set.items():
                  f.write(f"\n{set_name}:\n")
                  for icon in sorted(icons):
                      f.write(f"- {icon}\n")

      def main():
          with open(sys.argv[1], 'r') as f:
              config = json.load(f)

          output_base = Path(sys.argv[2])
          is_dev = sys.argv[3].lower() == "true"

          css_dir = output_base / "share/css"
          debug_dir = output_base / "debug"

          for dir in [css_dir, debug_dir]:
              dir.mkdir(parents=True, exist_ok=True)

          complete_css = ""
          used_icons_by_set = {}

          for icon_set in config["icon_sets"]:
              svg_data = process_svg_files(icon_set["source_path"], icon_set["path"])

              if is_dev:
                  used_icons = {f"{icon_set['prefix']}{name}" for name in svg_data.keys()}
              else:
                  used_icons = scan_templates(config["template_patterns"], icon_set["prefix"])

              used_icons_by_set[icon_set["name"]] = list(used_icons)
              complete_css += generate_css(icon_set, svg_data, used_icons)

          with open(css_dir / "svg-icons.css", 'w') as f:
              f.write(complete_css)

          # Generate and write JS
          js_dir = output_base / "share/js"
          js_dir.mkdir(parents=True, exist_ok=True)

          with open(js_dir / "icon-components.js", 'w') as f:
              f.write(generate_js(icon_set, svg_data, used_icons))

          write_debug_info(debug_dir, config["template_patterns"],
                          config["icon_sets"], used_icons_by_set)

      if __name__ == "__main__":
          main()
    '';
  };

in
pkgs.stdenv.mkDerivation {
  name = "svg-icon-processor";

  dontUnpack = true;

  buildInputs = [
    pkgs.python3
  ];

  buildPhase = ''
    # Copy template files from source
    cp -r ${projectRoot}/* ./

    # Run processing script
    python3 ${processorScript} ${configJson} $out ${if isDevelopment then "true" else "false"}
  '';

  installPhase = "true";
}
