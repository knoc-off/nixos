{ pkgs, icon-extractor-json-mapping, rustPlatform, lib }:
let
  # script to link content from nix-store to the project
  # link icons, fonts, etc.
  # mkdir static/fonts, static/icons and ln the content.
  #  ${pkgs.circle-flags}/share/circle-flags-svg/
  #  ${pkgs.material-icons}/share/fonts/opentype/
  #  ${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/

  linkStaticContent = let

    MaterialIconsRound-map = icon-extractor-json-mapping {
      inherit pkgs;
      package = pkgs.material-icons;
      fontPath = "/share/fonts/opentype/MaterialIconsRound-Regular.otf";
      prefix = "MaterialIconsRound";
    };

  in pkgs.writeScriptBin "link-static-content" ''
    mkdir -p ./static/fonts
    mkdir -p ./static/icons
    mkdir data

    ln -s ${pkgs.circle-flags}/share/circle-flags-svg/ ./static/icons/circle-flags-svg
    ln -s ${pkgs.material-icons}/share/fonts/opentype/ ./static/fonts/material-icons
    ln -s ${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/ ./static/icons/super-tiny-icons

    # Link Material Icons Round json mapping
    ln -s ${MaterialIconsRound-map}/share/glyph_unicode_map.json ./data/material-icons-round.json

  '';

  # script to build the css
  cssBuildScript = pkgs.writeScriptBin "tailwind-build" ''
    # Use Tailwind CSS standalone CLI to build the CSS
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
  ];

  buildInputs = [ pkgs.openssl.dev pkgs.pkg-config pkgs.zlib.dev ];

  # Build Tailwind CSS before compiling the Rust project
  preBuild = ''
    ${cssBuildScript}/bin/tailwind-build
    #pkgs.icon-extractor-json-mapping
  '';

  #postBuild = ''
  #  mkdir -p $out
  #  cp -r static $out
  #  cp -r templates $out
  #'';

  # shell hook when loading into the nix-shell ask to run the script
  shellHook = ''
    echo "Run 'link-static-content' to link static content"
    read -p "Run 'link-static-content' now? [Y/n] " -n 1 -r
    # run the script
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
      ${linkStaticContent}/bin/link-static-content
    fi
  '';

  # Set any necessary environment variables (if needed)
  meta = with lib; {
    description =
      "An Axum web application with Tailwind CSS integrated via Nix build";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with maintainers; [ yourName ];
  };
}
