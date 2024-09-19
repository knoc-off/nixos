{ pkgs, inputs, system, self, shell ? false }:

let
  rustPkgs = pkgs.extend (import inputs.rust-overlay);

  mkPkgOrShell = { path, args ? { }, callPackage ? pkgs.callPackage }:
    if shell then
      import path ({ inherit pkgs shell; } // args)
    else
      callPackage path ({ inherit shell; } // args);

  #wrapper = path: args: callPackage: importWithArgs { inherit path args callPackage;};

in rec {
  #test = importWithArgs ./test { };
  test = mkPkgOrShell {
    path = ./test;
    inherit (pkgs.python3Packages) callPackage;
  };

  spotify-adblock = pkgs.callPackage ./spotify-adblock { };
  pam-fprint-grosshack = pkgs.callPackage ./grosshack { };
  pam-wrapper = pkgs.callPackage ./pam-wrapper { };

  llm-cmd = mkPkgOrShell {
    path = ./llm-cmd;
    inherit (pkgs.python3Packages) callPackage;
  };

  # pkgs.python3Packages.callPackage ./llm-cmd { };

  ttok = pkgs.python3Packages.callPackage ./ttok { };

  marker = pkgs.python3Packages.callPackage ./marker { };

  texify = pkgs.callPackage ./texify { };
  gate = pkgs.callPackage ./gate { };
  ascii-silhouettify = pkgs.callPackage ./ascii { };

  neovim-nix = let
    nixvim = inputs.nixvim.legacyPackages.${system};

    customPkgs = import inputs.nixpkgs-unstable {
      inherit system;
      config = { allowUnfree = true; };
      overlays = [ inputs.nixneovimplugins.overlays.default ];
    };
  in {
    default = nixvim.makeNixvimWithModule {
      pkgs = customPkgs;
      module = import ./neovim/configurations;
    };
  };

  marlin = pkgs.callPackage ./marlin { };

  website = {
    actix-backend = rustPkgs.callPackage ./website/actix-backend { };
    portfolio = rustPkgs.callPackage ./website/portfolio { };
  };
  embeddedRust = rustPkgs.callPackage ./embedded-rust { };

  bevy-test = mkPkgOrShell {
    path = ./bevy/test;
    args = {
      rust-toolchain = rustPkgs.rust-bin.selectLatestNightlyWith (toolchain:
        toolchain.default.override {
          extensions = [ "rust-src" ];
          targets = [ "wasm32-unknown-unknown" ];
        });
    };
    inherit (rustPkgs) callPackage;
  };

  #nixpkgs#fira-code-nerdfont
  nerd-ext = import ./svg-tools/icon-extractor {
    inherit pkgs;
    fontPath =
      "${pkgs.fira-code-nerdfont}/share/fonts/truetype/NerdFonts/FiraCodeNerdFontMono-Regular.ttf";
  };
  material-icons-ext = import ./svg-tools/icon-extractor {
    inherit pkgs;
    fontPath =
      "${pkgs.material-icons}/share/fonts/opentype/MaterialIconsRound-Regular.otf";
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

  fdroid = let
    droidifyApk = pkgs.fetchurl {
      url =
        "https://github.com/Droid-ify/client/releases/download/v0.6.3/app-release.apk";
      sha256 = "sha256-InJOIXMuGdjNcdZQrcKDPJfSQTLFLjQ1QZhUjZppukQ=";
    };

    droidifyEmulator = pkgs.androidenv.emulateApp {
      name = "Droidify";
      package = pkgs.androidenv.androidPkgs_9_0.androidsdk;
      platformVersion = "28";
      abiVersion = "x86";
      systemImageType = "google_apis_playstore";
      app = droidifyApk;
    };

    droidifyWrapper = pkgs.stdenv.mkDerivation {
      name = "droidify-wrapper";
      buildInputs = [ pkgs.makeWrapper ];

      unpackPhase = "true";

      installPhase = ''
        mkdir -p $out/bin $out/share/applications

        # Create a wrapper script
        makeWrapper ${droidifyEmulator}/bin/run-test-emulator $out/bin/run-droidify

        # Create a .desktop file
        cat > $out/share/applications/droidify.desktop << EOF
        [Desktop Entry]
        Type=Application
        Name=Droid-ify
        Exec=$out/bin/run-droidify
        Icon=${
          pkgs.fetchurl {
            url =
              "https://raw.githubusercontent.com/Droid-ify/client/master/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png";
            sha256 = "sha256-r3hKlaMSnnNelZ67NMzuBWbieKcB2CcriTh7TSD+PK0=";
          }
        }
        Categories=Application;
        EOF
      '';
    };
  in droidifyWrapper;

  writeNuScript = name:
    (script:
      pkgs.writeTextFile rec {
        inherit name;
        text = "#!${pkgs.nushell}/bin/nu" + "\n" + script;

        executable = true;
        destination = "/bin/${name}";
      });
}

#packages
#builtins.mapAttrs mkPkgOrShell packages
