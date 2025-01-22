import json
import argparse
from pathlib import Path

def generate_icon_showcase(json_path: str, font_path: str, output_path: str = "icon_showcase.html"):
    # Read the icon mapping
    with open(json_path, 'r') as f:
        icons = json.load(f)

    # Get relative path to font file from the output HTML location
    font_path = Path(font_path)
    output_path = Path(output_path)
    relative_font_path = Path(font_path).relative_to(output_path.parent) if output_path.parent else font_path

    # Create HTML content
    html = f'''<!DOCTYPE html>
<html>
<head>
    <title>Material Icons Showcase</title>
    <style>
        @font-face {{
            font-family: 'MaterialIconsRound';
            font-style: normal;
            font-weight: 400;
            src: url("{relative_font_path}") format("opentype");
        }}

        .icon-container {{
            display: inline-flex;
            flex-direction: column;
            align-items: center;
            margin: 1rem;
            padding: 1rem;
            border: 1px solid #ccc;
            border-radius: 4px;
            width: 120px;
            height: 120px;
            text-align: center;
        }}

        .icon {{
            font-family: 'MaterialIconsRound';
            font-weight: 400;
            font-style: normal;
            font-size: 48px;
            line-height: 1;
            letter-spacing: normal;
            text-transform: none;
            display: inline-block;
            white-space: nowrap;
            word-wrap: normal;
            direction: ltr;
            -webkit-font-smoothing: antialiased;
            margin-bottom: 0.5rem;
        }}

        .icon-name {{
            font-family: monospace;
            font-size: 12px;
            word-break: break-all;
        }}

        .grid {{
            display: flex;
            flex-wrap: wrap;
            justify-content: center;
            padding: 1rem;
        }}

        .total-count {{
            text-align: center;
            padding: 1rem;
            font-family: monospace;
            font-size: 14px;
            color: #666;
        }}
    </style>
</head>
<body>
    <div class="total-count">Total Icons: {len(icons)}</div>
    <div class="grid">'''

    # Add each icon
    for name, code in icons.items():
        # Clean up name (remove 'uni' prefix if exists)
        display_name = name[3:] if name.startswith('uni') else name
        display_name = display_name.strip('_')

        html += f'''
        <div class="icon-container">
            <div class="icon">&#x{code};</div>
            <div class="icon-name">{display_name}</div>
        </div>'''

    html += '''
    </div>
</body>
</html>'''

    # Write the HTML file
    with open(output_path, 'w') as f:
        f.write(html)

    print(f"Generated showcase at: {output_path}")
    print(f"Total icons: {len(icons)}")

def main():
    parser = argparse.ArgumentParser(description='Generate an icon showcase HTML file')
    parser.add_argument('--json', '-j', required=True, help='Path to the JSON mapping file')
    parser.add_argument('--font', '-f', required=True, help='Path to the font file')
    parser.add_argument('--output', '-o', default='icon_showcase.html', help='Output HTML file path (default: icon_showcase.html)')

    args = parser.parse_args()

    generate_icon_showcase(args.json, args.font, args.output)

if __name__ == '__main__':
    main()
