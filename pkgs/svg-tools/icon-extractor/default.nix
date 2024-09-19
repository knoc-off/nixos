{ pkgs ? import <nixpkgs> { }, fontPath }:

pkgs.stdenv.mkDerivation {
  name = "extract-icons-svg";
  src = null;

  buildInputs = [ pkgs.fontforge pkgs.python3 ];

  unpackPhase = "true";

  buildPhase = ''
    mkdir -p svg_files
    cat << EOF > extract_glyphs.py
    import fontforge
    import os
    import csv
    import re

    def sanitize_filename(name):
        return re.sub(r'[<>:"/\\|?*]', '_', name)

    os.makedirs('svg_files', exist_ok=True)

    font = fontforge.open("${fontPath}")

    csv_filename = 'glyph_info.csv'
    csv_fields = ['GlyphName', 'Unicode', 'Filename', 'Width', 'Height', 'Left', 'Right']

    with open(csv_filename, 'w', newline=''') as csvfile:
        csvwriter = csv.DictWriter(csvfile, fieldnames=csv_fields)
        csvwriter.writeheader()

        for glyph in font.glyphs():
            if glyph.glyphname:
                sanitized_name = sanitize_filename(glyph.glyphname)
                filename = f'{sanitized_name}.svg'
                try:
                    glyph.export(f'svg_files/{filename}')
                except Exception as e:
                    print(f"Failed to export {glyph.glyphname}: {str(e)}")
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

    print("Extraction complete. SVG files and glyph_info.csv have been created.")
    EOF

    fontforge -script extract_glyphs.py
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
