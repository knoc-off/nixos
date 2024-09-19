{ pkgs ? import <nixpkgs> {}, fontPath, color ? "#000000", iconName ? null }:

pkgs.stdenv.mkDerivation {
  name = "extract-icons-svg";
  src = null;

  buildInputs = [ pkgs.fontforge pkgs.python3 pkgs.python3Packages.setuptools ];

  unpackPhase = "true";

  buildPhase = ''
    mkdir -p svg_files
    cat << EOF > extract_glyphs.py
    import fontforge
    import os
    import csv
    import re
    import xml.etree.ElementTree as ET

    def sanitize_filename(name):
        return re.sub(r'[<>:"/\\|?*]', '_', name)

    def apply_color(svg_file, color):
        tree = ET.parse(svg_file)
        root = tree.getroot()
        for elem in root.iter():
            if 'fill' in elem.attrib:
                elem.set('fill', color)
        tree.write(svg_file)

    os.makedirs('svg_files', exist_ok=True)

    font = fontforge.open("${fontPath}")

    csv_filename = 'glyph_info.csv'
    csv_fields = ['GlyphName', 'Unicode', 'Filename', 'Width', 'Height', 'Left', 'Right']

    with open(csv_filename, 'w', newline=''') as csvfile:
        csvwriter = csv.DictWriter(csvfile, fieldnames=csv_fields)
        csvwriter.writeheader()

        for glyph in font.glyphs():
            if glyph.glyphname:
                if ${if iconName == null then "True" else "glyph.glyphname == '${iconName}'"}:
                    sanitized_name = sanitize_filename(glyph.glyphname)
                    filename = f'{sanitized_name}.svg'
                    try:
                        glyph.export(f'svg_files/{filename}')
                        apply_color(f'svg_files/{filename}', '${color}')
                    except Exception as e:
                        print(f"Failed to export or color {glyph.glyphname}: {str(e)}")
                        continue

                    unicode_value = f'U+{glyph.unicode:04X}' if glyph.unicode != -1 else 'N/A'
                    glyph_info = {
                        'GlyphName': glyph.glyphname,
                        'Unicode': unicode_value,
                        'Filename': filename,
                        'Width': glyph.width,
                        'Height': glyph.vwidth,
                        'Left': glyph.left_side_bearing,
                        'Right': glyph.right_side_bearing
                    }

                    csvwriter.writerow(glyph_info)

                    if ${if iconName == null then "False" else "True"}:
                        break

    print("Extraction complete. SVG files and glyph_info.csv have been created.")
    EOF

    fontforge -lang=py -c 'import fontforge; exec(open("extract_glyphs.py").read())'
  '';

  installPhase = ''
    mkdir -p $out/svg_files
    cp -r svg_files/* $out/svg_files/
    cp glyph_info.csv $out/
  '';

  meta = with pkgs.lib; {
    description = "Extract SVG data and glyph information from a specified icons font package";
    license = licenses.mit;
    maintainers = [ maintainers.yourself ];
    platforms = platforms.all;
  };
}
