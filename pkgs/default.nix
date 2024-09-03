{
  pkgs,
  inputs,
  ...
}: rec {
  spotify-adblock = pkgs.callPackage ./spotify-adblock {};
  pam-fprint-grosshack = pkgs.callPackage ./grosshack {};
  pam-wrapper = pkgs.callPackage ./pam-wrapper {};
  llm-cmd = pkgs.python3Packages.callPackage ./llm-cmd {};
  ttok = pkgs.python3Packages.callPackage ./ttok {};
  poe = pkgs.python3Packages.callPackage ./poe-llm-api {};
  gate = pkgs.callPackage ./gate {};
  ascii-silhouettify = pkgs.callPackage ./ascii {};

  neovim-nix = let
    nixvim = inputs.nixvim.legacyPackages.${pkgs.system};

    customPkgs = import inputs.nixpkgs-unstable {
      inherit (pkgs) system;
      config = {allowUnfree = true;};
      overlays = [inputs.nixneovimplugins.overlays.default];
    };
  in {
    default = nixvim.makeNixvimWithModule {
      pkgs = customPkgs;
      module = import ./neovim/configurations;
    };
  };

  marlin = pkgs.callPackage ./marlin {};

  website = let
    #rust-overlay = inputs.rust-overlay;
    rustPkgs = pkgs.extend (import inputs.rust-overlay);
  in {
    actix-backend = rustPkgs.callPackage ./website/actix-backend {};
    portfolio = rustPkgs.callPackage ./website/portfolio {};
  };

  # This lets me use font glyphs as SVG's for places that dont accept SVG.
  material-icons-ext = import ./svg-tools/icon-extractor {
    inherit pkgs;
    fontPath = "${pkgs.material-icons}/share/fonts/opentype/MaterialIconsRound-Regular.otf";
  };

  writeRustScript = name: script:
    pkgs.stdenv.mkDerivation {
      inherit name;
      buildInputs = [ pkgs.rustc pkgs.cargo pkgs.openssl pkgs.pkg-config ];
      src = pkgs.writeTextFile {
        name = "Cargo.toml";
        text = ''
          [package]
          name = "${name}"
          version = "0.1.0"
          edition = "2021"

          [dependencies]
          clap = "3.1.6"
          anyhow = "1.0"
          fd-find = "8.3.0"
          skim = "0.9.4"
        '';
      };
      buildPhase = ''
        mkdir src
        cat > src/main.rs << EOF
        ${script}
        EOF
        cargo build --release
      '';
      installPhase = ''
        mkdir -p $out/bin
        cp target/release/${name} $out/bin/${name}
      '';
    };

  writeNuScript = name: (script:
    pkgs.writeTextFile rec {
      inherit name;
      text = "#!${pkgs.nushell}/bin/nu" + "\n" + script;

      executable = true;
      destination = "/bin/${name}";
    });
}
