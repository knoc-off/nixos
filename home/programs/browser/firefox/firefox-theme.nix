# firefox-theme.nix
{ lib, stdenv, zip, writeText }:

{
  name ? "Nix Generated Theme",
  version ? "1.0",
  description ? "A Firefox theme generated with Nix",
  addonId ? "nix-theme@example.com",
  colors ? {
    toolbar = "#4a5568";
    toolbar_text = "#ffffff";
    frame = "#2d3748";
    tab_selected = "#4a5568";
    tab_text = "#ffffff";
    tab_background_text = "#cbd5e0";
    bookmark_text = "#ffffff";
    toolbar_field = "#2d3748";
    toolbar_field_text = "#ffffff";
  }
}:

let
  manifest = writeText "manifest.json" ''
    {
      "manifest_version": 2,
      "name": "${name}",
      "version": "${version}",
      "description": "${description}",
      "theme": {
        "colors": ${builtins.toJSON colors}
      }
    }
  '';
in
stdenv.mkDerivation {
  pname = lib.strings.sanitizeDerivationName name;
  inherit version;

  buildInputs = [ zip ];

  dontUnpack = true;

  buildPhase = ''
    # Create XPI (ZIP file)
    cp ${manifest} ./manifest.json
    zip -r "${addonId}.xpi" manifest.json
  '';

  installPhase = ''
    dst="$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}"
    mkdir -p "$dst"
    install -v -m644 "${addonId}.xpi" "$dst/${addonId}.xpi"
  '';

  meta = {
    description = description;
    platforms = lib.platforms.all;
  };

  passthru = { inherit addonId; };
}
