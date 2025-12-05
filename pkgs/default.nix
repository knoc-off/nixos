# these packages can oftem be used as devshells but not always
{
  pkgs,
  lib,
  inputs,
  system,
  upkgs,
  color-lib,
  theme,
  ...
}: let
  rustPkgs = pkgs.extend (import inputs.rust-overlay);

  rustPkgs-fenix = upkgs.extend inputs.fenix.overlays.default;

  neovim-plugins = import ./neovim-plugins {inherit (pkgs) vimUtils lua;};

  rustPlatform = rustPkgs-fenix.makeRustPlatform {
    cargo = rustPkgs-fenix.fenix.minimal.toolchain;
    rustc = rustPkgs-fenix.fenix.minimal.toolchain;
  };

  rustToolchain-wasm = rustPkgs-fenix.fenix.combine [
    rustPkgs-fenix.fenix.complete.toolchain
    rustPkgs-fenix.fenix.targets.wasm32-unknown-unknown.latest.rust-std
  ];

  rustPlatform-wasm = rustPkgs-fenix.makeRustPlatform {
    cargo = rustToolchain-wasm;
    rustc = rustToolchain-wasm;
  };
in rec {
  materia-theme = pkgs.callPackage ./matera-theme {
    configBase16 = {
      name = "materia-theme";
      kind = "dark";
      colors = theme.dark;
    };
  };

  hyprkan = pkgs.python3Packages.callPackage ./hyprkan {};
  colorscad = pkgs.callPackage ./colorscad {};
  rcon-cli = pkgs.callPackage ./rcon-cli {};
  grosshack = pkgs.callPackage ./grosshack {};
  blink_led = pkgs.callPackage ./blinkFW13LED {};
  triliumNext = pkgs.callPackage ./triliumNext {};
  spotify-adblock = pkgs.callPackage ./spotify-adblock {};
  llm-cmd = pkgs.pythonPackages.callPackage ./llm-cmd {};
  ttok = pkgs.pythonPackages.callpackage ./ttok {};
  wrap = pkgs.pythonPackages.callPackage ./wrap-codeblocks {};
  nixx = pkgs.pythonPackages.callPackage ./nixx-script {};

  replicate-bridge = upkgs.pythonPackages.callPackage ./replicate {};
  marker = pkgs.pythonPackages.callPackage ./marker {};
  texify = pkgs.callPackage ./texify {};
  gate = pkgs.callPackage ./gate {};
  ascii-silhouettify = pkgs.callPackage ./ascii {};

  tabler-icons = pkgs.callPackage ./tabler-icons {};

  # Add React Native app package
  react-native-app = pkgs.callPackage ./react-native-app {
    androidSdk = pkgs.androidenv.androidPkgs_9_0.sdk;
    inherit
      (pkgs.darwin.apple_sdk.frameworks)
      CoreServices
      Foundation
      UIKit
      Security
      ;
    inherit
      (pkgs)
      nodejs_20
      yarn
      watchman
      cocoapods
      jdk17
      gradle
      ;
  };

  embeddedRust = rustPkgs.callPackage ./embedded-rust {};
  games = {
    bevy = rustPkgs.callPackage ./bevy {};
    bevy-game-of-life = rustPkgs.callPackage ./games/bevy-game-of-life {};
    bevy-simple = rustPkgs.callPackage ./games/bevy-simple {};
  };

  spider-cli = rustPkgs.callPackage ./spider {};
  csv-tui = rustPkgs.callPackage ./csv-tui-viewer {};
  tabiew = rustPkgs-fenix.callPackage ./tabiew {inherit rustPlatform;};
  cli-ai = rustPkgs-fenix.callPackage ./cli-ai {inherit rustPlatform;};
  marki = rustPkgs-fenix.callPackage ./marki {inherit rustPlatform;};
  marki-wasm = rustPkgs-fenix.callPackage ./marki-wasm {rustPlatform = rustPlatform-wasm;};
  recipt-printer = rustPkgs-fenix.callPackage ./recipt-printer {
    fenix = rustPkgs-fenix.fenix;
  };
  esp32-train-time = rustPkgs-fenix.callPackage ./esp32-train-time {
    fenix = rustPkgs-fenix.fenix;
  };

  inherit rustPkgs-fenix;
  inherit (inputs) fenix;

  website = {
    portfolio = rustPkgs.callPackage ./website/portfolio {};
    axum = rustPkgs-fenix.callPackage ./website/axum {
      inherit rustPlatform tabler-icons;
    };

    axum-login-test = rustPkgs.callPackage ./website/login-test {inherit tabler-icons;};
  };
  AOC24 = {
    day1 = rustPkgs.callPackage ./AdventOfCode2024/Day1 {};
    day2 = rustPkgs.callPackage ./AdventOfCode2024/Day2 {};
  };
  nx = config_dir: hostname: rustPkgs.callPackage ./nx-script {inherit config_dir hostname;};

  yek = rustPkgs.callPackage ./yek {};

  neovim-nix = let
    customPkgs = import inputs.nixpkgs-unstable {
      inherit system;
      config = {
        allowUnfree = true;
      };
      overlays = [
        inputs.nixneovimplugins.overlays.default
        neovim-plugins.overlay

        (final: prev: {
          neovim-unwrapped = prev.neovim-unwrapped.overrideAttrs (old: {
            #patches = old.patches ++ [
            #  # Fix byte index encoding bounds.
            #  # - https://github.com/neovim/neovim/pull/30747
            #  # - https://github.com/nix-community/nixvim/issues/2390
            #  (final.fetchpatch {
            #    name = "fix-lsp-str_byteindex_enc-bounds-checking-30747.patch";
            #    url =
            #      "https://patch-diff.githubusercontent.com/raw/neovim/neovim/pull/30747.patch";
            #    hash = "sha256-2oNHUQozXKrHvKxt7R07T9YRIIx8W3gt8cVHLm2gYhg=";
            #  })
            #];
          });
        })
      ];
    };
    nixvim = inputs.nixvim.legacyPackages.${system};
  in {
    default = nixvim.makeNixvimWithModule {
      pkgs = customPkgs;
      extraSpecialArgs = {inherit color-lib theme;};
      module = {
        imports = [./neovim/configurations/lazy-loading.nix];
      };
    };
    minimal = nixvim.makeNixvimWithModule {
      pkgs = customPkgs;
      extraSpecialArgs = {inherit color-lib theme;};
      module = {
        imports = [./neovim/configurations/minimal.nix];
      };
    };
  };

  #nerd-ext = import ./svg-tools/icon-extractor {
  #  inherit pkgs;
  #  fontPath =
  #    "${pkgs.fira-code-nerdfont}/share/fonts/truetype/NerdFonts/FiraCodeNerdFontMono-Regular.ttf";
  #};

  #material-icons-ext = import ./svg-tools/icon-extractor {
  #  inherit pkgs;
  #  fontPath =
  #    "${pkgs.material-icons}/share/fonts/opentype/MaterialIconsRound-Regular.otf";
  #};

  #  fdroid = let
  #    droidifyApk = pkgs.fetchurl {
  #      url =
  #        "https://github.com/Droid-ify/client/releases/download/v0.6.3/app-release.apk";
  #      sha256 = "sha256-InJOIXMuGdjNcdZQrcKDPJfSQTLFLjQ1QZhUjZppukQ=";
  #    };
  #    droidifyEmulator = pkgs.androidenv.emulateApp {
  #      name = "Droidify";
  #      package = pkgs.androidenv.androidPkgs_9_0.androidsdk;
  #      platformVersion = "28";
  #      abiVersion = "x86";
  #      systemImageType = "google_apis_playstore";
  #      app = droidifyApk;
  #    };
  #  in droidifyEmulator;

  astal-widget-wrapper = {
    path,
    entry,
    name,
  }: (pkgs.stdenvNoCC.mkDerivation rec {
    inherit name;
    src = path;

    nativeBuildInputs = [
      inputs.ags.packages.${system}.default
      pkgs.wrapGAppsHook
      pkgs.gobject-introspection
    ];

    buildInputs = with inputs.astal.packages.${system}; [
      io

      apps
      astal3
      astal4
      auth
      battery
      bluetooth
      cava
      default
      docs
      greet
      hyprland
      mpris
      network
      notifd
      powerprofiles
      river
      tray
      wireplumber
    ];

    installPhase = ''
      # Copy the source to a fixed location
      mkdir -p $out/share/${name}
      cp -r ./* $out/share/${name}/

      # Create wrapper that runs ags with the copied source
      mkdir -p $out/bin
      makeWrapper ${inputs.ags.packages.${system}.default}/bin/ags $out/bin/${name} \
        --add-flags "run" \
        --add-flags "$out/share/${name}/${entry}" \
        --argv0 "$name"
    '';
  });

  astal-notifications-test = pkgs.stdenvNoCC.mkDerivation rec {
    name = "astal-notifications";
    src = ../home/desktop/astal/configs/notifications;

    nativeBuildInputs = [
      inputs.ags.packages.${system}.default
      pkgs.wrapGAppsHook
      pkgs.makeWrapper
      pkgs.nodejs
      pkgs.esbuild
      pkgs.dart-sass
      pkgs.blueprint-compiler
    ];

    buildInputs = with inputs.astal.packages.${system}; [
      astal3
      io
      notifd
      mpris
      network
      battery
      bluetooth
      powerprofiles
      tray

      # Core GObject libraries
      pkgs.gjs
      pkgs.glib
      pkgs.gobject-introspection
      pkgs.gtk3
      pkgs.gtk4
      pkgs.libadwaita

      # GVFS fix
      (pkgs.gvfs.override {glib = pkgs.glib;})
      pkgs.gsettings-desktop-schemas

      # Astal GJS environment
      inputs.ags.packages.${system}.gjs
    ];

    buildPhase = ''
      export HOME=$TMPDIR
      export PATH="${
        lib.makeBinPath [
          pkgs.nodejs
          pkgs.esbuild
          pkgs.dart-sass
          pkgs.blueprint-compiler
          inputs.ags.packages.${system}.default
        ]
      }:$PATH"

      echo "--- Setting up build environment ---"
      echo "--- Checking Astal GJS structure ---"
      ls -la ${inputs.ags.packages.${system}.gjs}/share/astal/gjs/

      echo "--- Running esbuild with externals ---"
      ${pkgs.esbuild}/bin/esbuild app.tsx \
        --bundle \
        --outfile=bundled-app.mjs \
        --format=esm \
        --platform=neutral \
        --target=es2022 \
        --sourcemap=inline \
        --loader:.js=jsx \
        --loader:.ts=tsx \
        --loader:.tsx=tsx \
        --loader:.css=text \
        --loader:.scss=text \
        --loader:.sass=text \
        --external:console \
        --external:system \
        --external:cairo \
        --external:gettext \
        --external:"file://*" \
        --external:"gi://*" \
        --external:"resource://*" \
        --external:"astal" \
        --external:"astal/*" \
        --define:SRC='"./"' \
        --log-level=warning \
        --color=true \
        --resolve-extensions=.ts,.tsx,.js,.jsx,.mjs

      if [ ! -f "bundled-app.mjs" ]; then
        echo "Error: esbuild failed to produce bundled-app.mjs"
        exit 1
      fi

      echo "--- esbuild bundling complete ---"
      echo "--- First 20 lines of bundle ---"
      head -20 bundled-app.mjs
      echo "--- End preview ---"
    '';

    installPhase = ''
      mkdir -p $out/share/${name}

      # Copy the ES module bundle
      cp bundled-app.mjs $out/share/${name}/app.mjs

      # Create symlink to astal modules for runtime resolution
      mkdir -p $out/share/${name}/node_modules
      ln -sf ${inputs.ags.packages.${system}.gjs}/share/astal/gjs $out/share/${name}/node_modules/astal

      # Copy any other assets
      cp -r ./* $out/share/${name}/ || true

      mkdir -p $out/bin

      echo "--- Creating executable wrapper ---"
      makeWrapper ${pkgs.gjs}/bin/gjs $out/bin/${name} \
        --add-flags "--module" \
        --add-flags "$out/share/${name}/app.mjs" \
        --chdir "$out/share/${name}" \
        --prefix GJS_PATH : "$out/share/${name}/node_modules" \
        --prefix GJS_PATH : "${inputs.ags.packages.${system}.gjs}/share/astal/gjs" \
        --set GJS_DEBUG_TOPICS "JS ERROR;JS LOG;JS WARNING;MODULES" \
        --set GJS_DEBUG_OUTPUT stderr \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.astal3}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.io}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.notifd}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.astal3}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.mpris}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.network}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.battery}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.bluetooth}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.powerprofiles}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${inputs.ags.packages.${system}.tray}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${pkgs.glib}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${pkgs.gtk3}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${pkgs.gtk4}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${pkgs.libadwaita}/lib/girepository-1.0" \
        --prefix GI_TYPELIB_PATH : "${pkgs.gobject-introspection}/lib/girepository-1.0" \
        --prefix GIO_MODULE_PATH : "${pkgs.gvfs}/lib/gio/modules" \
        --prefix XDG_DATA_DIRS : "$out/share:${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}" \
        --prefix PATH : "${lib.makeBinPath [inputs.astal.packages.${system}.io]}" \
        --argv0 "$name"

      echo "--- Wrapper created successfully ---"
    '';

    preFixup = ''
      echo "--- Applying gappsWrapperArgs in preFixup ---"
      gappsWrapperArgs+=(
        --prefix LD_LIBRARY_PATH : "${pkgs.glib}/lib"
        --unset GVFS_DISABLE_FUSE
        --set GLIB_NETWORKING_USE_PKCS11 0
      )
      echo "--- gappsWrapperArgs applied ---"
    '';

    meta = {
      description = "Astal-based notification daemon bundled with esbuild";
      platforms = lib.platforms.linux;
    };
  };

  icon-extractor-json-mapping = {
    package,
    fontPath,
    prefix ? "",
  }:
    import ./svg-tools/icon-extractor/json-mapping.nix {
      inherit
        pkgs
        package
        fontPath
        prefix
        ;
    };

  icon-pruner = {
    package,
    fontPath,
    iconList,
  }:
    import ./svg-tools/icon-extractor/prune-font-file.nix {
      inherit
        pkgs
        package
        fontPath
        iconList
        ;
    };

  pruned-font = icon-pruner {
    package = pkgs.material-icons;
    fontPath = "/share/fonts/opentype/MaterialIconsOutlined-Regular.otf";
    iconList = [
      "map"
      "c"
      "d"
      "e"
      "f"
      "g"
    ];
  };

  nerd-map = icon-extractor-json-mapping {
    package = pkgs.fira-code-nerdfont;
    fontPath = "/share/fonts/truetype/NerdFonts/FiraCodeNerdFontMono-Regular.ttf";
    prefix = "FiraCode";
  };

  mkComplgenScript = {
    name,
    scriptContent,
    grammar,
    runtimeDeps ? [],
  }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "0.1.0";

      # Dependencies needed only during the build process
      nativeBuildInputs = [
        pkgs.complgen
        pkgs.makeWrapper
      ];

      # Dependencies needed by the script itself at runtime
      # These are made available in the Nix store
      buildInputs = runtimeDeps;

      env.grammar = grammar;
      env.scriptContent = scriptContent;

      src = pkgs.lib.cleanSource ./.;

      installPhase = ''
        runHook preInstall

        # Ensure output directories exist
        mkdir -p $out/bin
        mkdir -p $out/share/bash-completion/completions
        mkdir -p $out/share/fish/vendor_completions.d
        mkdir -p $out/share/zsh/site-functions

        # Write the script from the environment variable
        echo -n "$scriptContent" > $out/bin/${name} # Use name for the executable
        chmod +x $out/bin/${name}

        # Write the grammar from the environment variable to a temporary file
        echo -n "$grammar" > grammar.usage

        # Generate completions using complgen aot
        echo "Generating completions for ${name}..."
        ${pkgs.complgen}/bin/complgen aot grammar.usage --bash-script $out/share/bash-completion/completions/${name}
        ${pkgs.complgen}/bin/complgen aot grammar.usage --fish-script $out/share/fish/vendor_completions.d/${name}.fish
        ${pkgs.complgen}/bin/complgen aot grammar.usage --zsh-script $out/share/zsh/site-functions/_${name}

        # Basic check if generation produced files (adjust if needed)
        if [ ! -s "$out/share/fish/vendor_completions.d/${name}.fish" ]; then
            echo "Error: Fish completion generation likely failed for ${name} (output file empty or missing)."
        fi

        rm grammar.usage # Clean up temporary grammar file

        # Wrap the program to include runtime dependencies in PATH
        # Ensures that commands from runtimeDeps (like python) are found
        local rt_path="${pkgs.lib.makeBinPath runtimeDeps}"
        echo "Wrapping ${name} with PATH: $rt_path"
        wrapProgram $out/bin/${name} --prefix PATH : "$rt_path"

        runHook postInstall
      '';

      meta = {
        description = "Script '${name}' with multi-shell completions via complgen";
        # license = pkgs.lib.licenses.mit; # Set an appropriate license
        platforms = pkgs.lib.platforms.all;
      };
    };

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
