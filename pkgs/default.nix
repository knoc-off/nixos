{ pkgs, lib, inputs, system, self, upkgs }:
let
  rustPkgs = pkgs.extend (import inputs.rust-overlay);
  neovim-plugins = import ./neovim-plugins { inherit (pkgs) vimUtils lua; };
in rec {
  rcon-cli = pkgs.callPackage ./rcon-cli { };
  grosshack = pkgs.callPackage ./grosshack { };
  blink_led = pkgs.callPackage ./blinkFW13LED { };
  triliumNext = pkgs.callPackage ./triliumNext { };
  spotify-adblock = pkgs.callPackage ./spotify-adblock { };
  llm-cmd = pkgs.python3Packages.callPackage ./llm-cmd { };
  ttok = pkgs.python3Packages.callPackage ./ttok { };
  replicate-bridge = upkgs.python3Packages.callPackage ./replicate { };
  marker = pkgs.python3Packages.callPackage ./marker { };
  texify = pkgs.callPackage ./texify { };
  gate = pkgs.callPackage ./gate { };
  ascii-silhouettify = pkgs.callPackage ./ascii { };

  # Add React Native app package
  react-native-app = pkgs.callPackage ./react-native-app {
    androidSdk = pkgs.androidenv.androidPkgs_9_0.sdk;
    inherit (pkgs.darwin.apple_sdk.frameworks) CoreServices Foundation UIKit Security;
    inherit (pkgs) nodejs_20 yarn watchman cocoapods jdk17 gradle;
  };

  neovim-nix = let
    customPkgs = import inputs.nixpkgs-unstable {
      inherit system;
      config = { allowUnfree = true; };
      overlays = [ inputs.nixneovimplugins.overlays.default neovim-plugins.overlay ];
    };
    nixvim = inputs.nixvim.legacyPackages.${system};
  in {
    default = nixvim.makeNixvimWithModule {
      pkgs = customPkgs;
      module = {
        imports = [ ./neovim/configurations ];
      };
    };
  };

  website = {
    actix-backend = rustPkgs.callPackage ./website/actix-backend { };
    portfolio = rustPkgs.callPackage ./website/portfolio { };
  };

  embeddedRust = rustPkgs.callPackage ./embedded-rust { };

  nx = config_dir: hostname:
    rustPkgs.callPackage ./nx-script { inherit config_dir hostname; };

  bevy = rustPkgs.callPackage ./bevy/default.nix { };

  nerd-ext = import ./svg-tools/icon-extractor {
    inherit pkgs;
    fontPath = "${pkgs.fira-code-nerdfont}/share/fonts/truetype/NerdFonts/FiraCodeNerdFontMono-Regular.ttf";
  };

  material-icons-ext = import ./svg-tools/icon-extractor {
    inherit pkgs;
    fontPath = "${pkgs.material-icons}/share/fonts/opentype/MaterialIconsRound-Regular.otf";
  };

  fdroid = let
    droidifyApk = pkgs.fetchurl {
      url = "https://github.com/Droid-ify/client/releases/download/v0.6.3/app-release.apk";
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
  in droidifyEmulator;

  writeNuScript = name: script:
    pkgs.writeTextFile rec {
      inherit name;
      text = "#!${pkgs.nushell}/bin/nu" + "\n" + script;
      executable = true;
      destination = "/bin/${name}";
    };

  writeLuaScript = name: script:
    pkgs.writeTextFile {
      inherit name;
      text = ''
        #!${pkgs.lua}/bin/lua
        ${script}
      '';
      executable = true;
      destination = "/bin/${name}";
    };
}

