{pkgs ? import <nixpkgs> {}}:
pkgs.stdenv.mkDerivation rec {
  name = "modify-svg-color";
  version = "1.0";
  src = null;

  buildInputs = [pkgs.python3 pkgs.python3Packages.lxml];

  script = ''
    import sys
    from lxml import etree

    if len(sys.argv) != 4:
        print("Usage: modify_svg_color.py input.svg output.svg new_color")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    new_color = sys.argv[3]

    parser = etree.XMLParser(remove_blank_text=True)
    tree = etree.parse(input_file, parser)
    root = tree.getroot()

    for element in root.iter():
        if element.tag.endswith('path'):
            element.set('fill', new_color)

    tree.write(output_file, pretty_print=True)
  '';

  buildPhase = ''
    mkdir -p $out/bin
    echo "${script}" > $out/bin/modify_svg_color.py
    chmod +x $out/bin/modify_svg_color.py
  '';

  meta = with pkgs.lib; {
    description = "A script to modify the fill color of an SVG file";
    license = licenses.mit;
    maintainers = [maintainers.yourself];
    platforms = platforms.all;
  };
}
