import json
import glob
import re
from pathlib import Path
from typing import Dict, Set, List
from dataclasses import dataclass
import argparse


@dataclass
class FontConfig:
    file_path: str
    format: str


@dataclass
class IconConfig:
    base_class: str
    prefix: str
    path: str
    name: str
    font: FontConfig

    @classmethod
    def from_dict(cls, data: dict):
        font_data = data.get("font", {})
        return cls(
            base_class=data["base_class"],
            prefix=data["prefix"],
            path=data["path"],
            name=data["name"],
            font=FontConfig(**font_data) if font_data else None,
        )


class IconProcessor:
    def __init__(self, config_path: str):
        self.config = self._load_config(config_path)
        self.icon_sets = self._load_icon_sets()
        self.used_icons_by_font = {}  # New: Track icons by file

    def _load_config(self, config_path: str) -> Dict:
        with open(config_path, "r") as f:
            return json.load(f)

    def _load_icon_sets(self) -> List[IconConfig]:
        return [IconConfig.from_dict(icon_set) for icon_set in self.config["icon_sets"]]

    def _load_icon_mappings(self, path: str) -> Dict[str, str]:
        with open(path, "r") as f:
            return json.load(f)

    def scan_templates_for_icons(self, icon_set: IconConfig) -> Set[str]:
        used_icons = set()
        pattern = f"{icon_set.prefix}([a-zA-Z0-9-_]+)"

        print(f"\nScanning for pattern: {pattern}")
        for template_pattern in self.config["template_patterns"]:
            print(f"Looking in: {template_pattern}")
            for template_file in glob.glob(template_pattern):
                with open(template_file, "r") as f:
                    content = f.read()
                    matches = re.findall(pattern, content)
                    if matches:
                        print(f"Found in {template_file}: {matches}")
                    used_icons.update(matches)

        # Track icons by font file
        font_file = Path(icon_set.font.file_path).name
        if font_file not in self.used_icons_by_font:
            self.used_icons_by_font[font_file] = []
        self.used_icons_by_font[font_file].extend(list(used_icons))

        print(f"Total icons found: {used_icons}")
        return used_icons

    def generate_css_for_set(self, icon_set: IconConfig, used_icons: Set[str]) -> str:
        icon_mappings = self._load_icon_mappings(icon_set.path)
        print(f"\nIcon mappings loaded: {len(icon_mappings)} icons")
        print(f"Used icons to generate: {used_icons}")

        # Start with font-face definition
        css = f"""/* Generated {icon_set.name} CSS */
    @font-face {{
      font-family: '{icon_set.name}';
      font-style: normal;
      font-weight: 400;
      src: url("../fonts/{Path(icon_set.font.file_path).name}") format("{icon_set.font.format}");
    }}

    /* Base icon styles */
    .{icon_set.base_class} {{
      font-family: '{icon_set.name}';
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

        # Group all icons into a single selector for shared properties
        icon_selectors = []
        icon_contents = []

        for icon_name in used_icons:
            if icon_name in icon_mappings:
                selector = f".{icon_set.prefix}{icon_name}"
                icon_selectors.append(selector)
                icon_contents.append(
                    f"{selector}::before{{content:\"\\{icon_mappings[icon_name]}\"}}"
                )
            else:
                print(f"Warning: Icon '{icon_name}' not found in {icon_set.name} mappings")

        if icon_selectors:
            # Add shared properties for all icons
            css += f"{','.join(icon_selectors)} {{\n"
            css += f"  font-family: '{icon_set.name}';\n"
            css += "}\n\n"

            # Add individual content properties
            css += '\n'.join(icon_contents)

        return css

    def save_used_icons(self):
        # Create nested directory structure
        output_dir = Path("data/used_icons")
        output_dir.mkdir(parents=True, exist_ok=True)

        # Process each font's icons separately
        for font_file, icons in self.used_icons_by_font.items():
            # Remove any empty or invalid icons
            valid_icons = [icon for icon in icons if icon and isinstance(icon, str) and icon.strip()]
            if not valid_icons:
                valid_icons = []
                print(f"Warning: No icons found for {font_file}, using fallback")
            else:
                valid_icons = sorted(set(valid_icons))
                print(f"Font {font_file}: Found {len(valid_icons)} valid icons")

            # Create individual JSON file for each font
            basename = Path(font_file).stem
            output_path = output_dir / f"{basename}.json"

            with open(output_path, "w") as f:
                json.dump(valid_icons, f, indent=2)
                print(f"Written icon data to {output_path}:")
                print(json.dumps(valid_icons, indent=2))

    def process(self, development_mode=False):
        output_path = Path(self.config["output_css_path"])
        output_path.parent.mkdir(parents=True, exist_ok=True)

        complete_css = ""

        for icon_set in self.icon_sets:
            if development_mode:
                # In development mode, load all icons from the mapping
                icon_mappings = self._load_icon_mappings(icon_set.path)
                used_icons = set(icon_mappings.keys())
                # Fix font path to be relative to CSS file
                icon_set.font.file_path = (
                    "../fonts/" + Path(icon_set.font.file_path).name
                )
            else:
                used_icons = self.scan_templates_for_icons(icon_set)
                # Fix font path to be relative to CSS file
                icon_set.font.file_path = (
                    "../fonts/" + Path(icon_set.font.file_path).name
                )

            css = self.generate_css_for_set(icon_set, used_icons)
            complete_css += css
            print(f"Generated CSS for {len(used_icons)} {icon_set.name} icons")

        with open(output_path, "w") as f:
            f.write(complete_css)

        print(f"CSS file written to: {output_path}")

        if not development_mode:
            self.save_used_icons()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--development", action="store_true", help="Generate CSS for all icons"
    )
    args = parser.parse_args()

    processor = IconProcessor("icon_config.json")
    processor.process(development_mode=args.development)


if __name__ == "__main__":
    main()
