import json
import glob
import re
from pathlib import Path
from typing import Dict, Set, List
from dataclasses import dataclass

@dataclass
class IconConfig:
    base_class: str
    prefix: str
    path: str
    name: str

class IconProcessor:
    def __init__(self, config_path: str):
        self.config = self._load_config(config_path)
        self.icon_sets = self._load_icon_sets()

    def _load_config(self, config_path: str) -> Dict:
        with open(config_path, 'r') as f:
            return json.load(f)

    def _load_icon_sets(self) -> List[IconConfig]:
        icon_sets = []
        for icon_set in self.config['icon_sets']:
            icon_sets.append(IconConfig(
                base_class=icon_set['base_class'],
                prefix=icon_set['prefix'],
                path=icon_set['path'],
                name=icon_set['name']
            ))
        return icon_sets

    def _load_icon_mappings(self, path: str) -> Dict[str, str]:
        with open(path, 'r') as f:
            return json.load(f)

    def scan_templates_for_icons(self, icon_set: IconConfig) -> Set[str]:
        used_icons = set()
        pattern = f'{icon_set.prefix}([a-zA-Z0-9-_]+)'

        print(f"\nScanning for pattern: {pattern}")
        for template_pattern in self.config['template_patterns']:
            print(f"Looking in: {template_pattern}")
            for template_file in glob.glob(template_pattern):
                with open(template_file, 'r') as f:
                    content = f.read()
                    matches = re.findall(pattern, content)
                    if matches:
                        print(f"Found in {template_file}: {matches}")
                    # Convert matches to full icon names
                    full_matches = {f"MaterialIconsRound_{match}" for match in matches}
                    used_icons.update(full_matches)

        print(f"Total icons found: {used_icons}")
        return used_icons

    def generate_css_for_set(self, icon_set: IconConfig, used_icons: Set[str]) -> str:
        icon_mappings = self._load_icon_mappings(icon_set.path)
        print(f"\nIcon mappings loaded: {len(icon_mappings)} icons")
        print(f"Used icons to generate: {used_icons}")

        css = f"""/* Generated {icon_set.name} CSS */
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
}}\n\n"""

        for full_icon_name in used_icons:
            if full_icon_name in icon_mappings:
                # Extract the short name by removing the prefix
                short_name = full_icon_name.replace("MaterialIconsRound_", "")
                print(f"Generating CSS for: {short_name}")
                css += f'.{icon_set.prefix}{short_name}::before {{\n'
                css += f'  content: "\\{icon_mappings[full_icon_name]}";\n'
                css += '}\n\n'
            else:
                print(f"Warning: Icon '{full_icon_name}' not found in {icon_set.name} mappings")

        return css

    def process(self):
        output_path = Path(self.config['output_css_path'])
        output_path.parent.mkdir(parents=True, exist_ok=True)

        complete_css = ""

        for icon_set in self.icon_sets:
            used_icons = self.scan_templates_for_icons(icon_set)
            css = self.generate_css_for_set(icon_set, used_icons)
            complete_css += css
            print(f"Generated CSS for {len(used_icons)} {icon_set.name} icons")

        with open(output_path, 'w') as f:
            f.write(complete_css)

        print(f"CSS file written to: {output_path}")

def main():
    processor = IconProcessor('icon_config.json')
    processor.process()

if __name__ == "__main__":
    main()
