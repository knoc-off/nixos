{ pkgs, icon-extractor-json-mapping, icon-pruner, rustPlatform, lib }:
let
  fonts = [
    rec {
      package = pkgs.material-icons;
      fontPath = "/share/fonts/opentype/MaterialIconsRound-Regular.otf";
      mapping = icon-extractor-json-mapping { inherit package fontPath; };
      basename = builtins.baseNameOf fontPath;
      name = "MaterialIconsRound";
      base_class = "mi-round";
      prefix = "MIRound_";
    }
    rec {
      package = pkgs.material-icons;
      fontPath = "/share/fonts/opentype/MaterialIconsSharp-Regular.otf";
      mapping = icon-extractor-json-mapping { inherit package fontPath; };
      basename = builtins.baseNameOf fontPath;
      name = "MaterialIconsSharp";
      base_class = "mi-sharp";
      prefix = "MISharp_";
    }
  ];

  # Generate icon config JSON
  iconConfig = pkgs.writeText "icon_config.json" (builtins.toJSON {
    template_patterns = [
      "templates/*.html"
      "templates/**/*.html"
    ];
    output_css_path = "static/css/icons.css";
    icon_sets = map (font: {
      inherit (font) name base_class prefix;
      path = "data/${font.basename}.json";
      font = {
        file_path = "${font.basename}";  # Just the filename, path will be handled in CSS
        format = "opentype";
      };
    }) fonts;
  });

  linkStaticContent = pkgs.writeScriptBin "link-static-content" ''
    # Clean up existing links and directories
    rm -f ./static/fonts/* ./static/icons/* ./data/*.json ./icon_config.json

    mkdir -p ./static/fonts
    mkdir -p ./static/icons
    mkdir -p ./static/css
    mkdir -p data

    # Copy icon config
    cp ${iconConfig} ./icon_config.json

    # Link regular static content
    ln -sf ${pkgs.circle-flags}/share/circle-flags-svg/ ./static/icons/circle-flags-svg
    ln -sf ${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/ ./static/icons/super-tiny-icons

    # Link full fonts for development
    ${builtins.concatStringsSep "\n" (map (font: ''
      ln -sf ${font.package}${font.fontPath} ./static/fonts/${font.basename}
      ln -sf ${font.mapping}/share/glyph_unicode_map.json ./data/${font.basename}.json
    '') fonts)}

    # Generate full CSS with all icons for development
    python3 ./used-icons.py $1
  '';

  # script to build the css
  cssBuildScript = pkgs.writeScriptBin "tailwind-build" ''
    ${pkgs.tailwindcss}/bin/tailwindcss \
      -i ./styles.css \
      -o ./static/css/styles.css \
      -c ./tailwind.config.js \
      --minify
  '';

in rustPlatform.buildRustPackage rec {
  pname = "axum-website";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    (rust-bin.stable."1.82.0".default.override {
      extensions = [ "rust-src" ];
      targets = [ "wasm32-unknown-unknown" ];
    })
    pkg-config
    cssBuildScript
    linkStaticContent
    tailwindcss
    python3
  ];

  buildInputs = [ pkgs.openssl.dev pkgs.pkg-config pkgs.zlib.dev ];

  # In the buildRustPackage part, update preBuild:
  preBuild = ''
    # Generate directories
    mkdir -p ./static/fonts
    mkdir -p ./static/css
    mkdir -p data

    # Generate used icons JSON (without development flag)
    python3 ./used-icons.py

    # Load used icons
    usedIcons=$(cat ./data/used_icons.json)

    # Link pruned fonts for production build
    ${builtins.concatStringsSep "\n" (map (font: ''
      icons_list=$(echo "$usedIcons" | jq -r '.["${font.basename}"] // []')
      pruned_font=$(${icon-pruner {
        package = font.package;
        fontPath = font.fontPath;
        iconList = "$icons_list";
      }}/share/fonts/*)
      ln -sf $pruned_font ./static/fonts/${font.basename}
      ln -sf ${font.mapping}/share/glyph_unicode_map.json ./data/${font.basename}.json
    '') fonts)}

    # Build CSS
    ${cssBuildScript}/bin/tailwind-build
  '';

  #  shellHook = ''
  #    echo "Run 'link-static-content' to link static content"
  #    read -p "Run 'link-static-content' now? [Y/n] " -n 1 -r
  #    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
  #      ${linkStaticContent}/bin/link-static-content
  #    fi
  #  '';

  # shellHook = ''
  #   echo "Run 'link-static-content' to link static content"
  #   read -p "Run 'link-static-content' now? [Y/n] " -n 1 -r
  #   if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
  #     ${linkStaticContent}/bin/link-static-content
  #   fi

  #   echo -e "\nLinking pruned fonts for testing..."

  #   # Clean up testing directory and any stray symlinks
  #   rm -rf data/testing MaterialIcons*
  #   mkdir -p data/testing/fonts
  #   mkdir -p data/testing/data

  #   # Generate used icons JSON
  #   python3 ./used-icons.py 2>/dev/null  # Suppress warnings

  #   # Create a default icon list if none exists
  #   if [ ! -f ./data/used_icons.json ]; then
  #     echo '{"MaterialIconsRound-Regular.otf": ["home"], "MaterialIconsSharp-Regular.otf": ["home"]}' > ./data/used_icons.json
  #   fi

  #   # Load used icons
  #   usedIcons=$(cat ./data/used_icons.json)

  #   # Link pruned fonts for testing
  #   ${builtins.concatStringsSep "\n" (map (font: ''
  #     icons_list=$(echo "$usedIcons" | jq -r '.["${font.basename}"] // ["home"]')
  #     if [ -n "$icons_list" ]; then
  #       pruned_font_path=$(${icon-pruner {
  #         package = font.package;
  #         fontPath = font.fontPath;
  #         iconList = "$icons_list";
  #       }}/share/fonts/*)
  #       if [ -f "$pruned_font_path" ]; then
  #         cp "$pruned_font_path" "./data/testing/fonts/${font.basename}"
  #       fi
  #     fi
  #     ln -sf ${font.mapping}/share/glyph_unicode_map.json "./data/testing/data/${font.basename}.json"
  #   '') fonts)}

  #   echo "Pruned fonts linked in data/testing/"
  # '';

  shellHook = ''
    echo "Run 'link-static-content' to link static content"
    read -p "Run 'link-static-content' now? [Y/n] " -n 1 -r
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
      ${linkStaticContent}/bin/link-static-content --development
    fi
  '';

  meta = with lib; {
    description =
      "An Axum web application with Tailwind CSS integrated via Nix build";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with maintainers; [ knoff ];
  };
}
