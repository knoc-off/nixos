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
  # Theme that is generated based off of my base 16 theme.
  materia-theme = pkgs.callPackage ./matera-theme {
    configBase16 = {
      name = "materia-theme";
      kind = "dark";
      colors = theme.dark;
    };
  };

  # hyprland integration for kanata
  hyprkan = pkgs.python3Packages.callPackage ./hyprkan {};

  # openscad colors are outputted for 3mf
  colorscad = pkgs.callPackage ./colorscad {};

  # remote console for minecraft.
  rcon-cli = pkgs.callPackage ./rcon-cli {};

  # pam module supports both fingerprint, and password
  grosshack = pkgs.callPackage ./grosshack {};

  # LD_PRELOAD to block spotify ads.
  spotify-adblock = pkgs.callPackage ./spotify-adblock {};

  # minecraft router
  gate = pkgs.callPackage ./gate {};

  # img to ascii
  ascii = pkgs.callPackage ./ascii {};

  tabler-icons = pkgs.callPackage ./tabler-icons {};

  # Anki card decks generator
  marki = rustPkgs-fenix.callPackage ./marki {inherit rustPlatform;};
  layer-shika = rustPkgs-fenix.callPackage ./layer-shika {inherit rustPlatform;};
  relm4-layershell = rustPkgs-fenix.callPackage ./relm4-layershell {inherit rustPlatform;};
  marki-wasm = rustPkgs-fenix.callPackage ./marki-wasm {rustPlatform = rustPlatform-wasm;};

  # rust fuse fileSystem that integrates with taskwarrior sql db
  fuse-taskchampion = rustPkgs-fenix.callPackage ./fuse-taskchampion {
    fenix = rustPkgs-fenix.fenix;
  };

  # Converts markdown to ESC-POS epson escape print commands
  recipt-printer = rustPkgs-fenix.callPackage ./recipt-printer {
    fenix = rustPkgs-fenix.fenix;
  };

  # LSP multiplexer - share language servers between editor instances
  lspmux = rustPkgs-fenix.callPackage ./lspmux {
    fenix = rustPkgs-fenix.fenix;
  };

  # Attempt at embedded esp32.
  esp32-train-time = rustPkgs-fenix.callPackage ./esp32-train-time {
    fenix = rustPkgs-fenix.fenix;
  };

  # Modern programming language for CAD
  microcad = rustPkgs-fenix.callPackage ./microcad {
    fenix = rustPkgs-fenix.fenix;
  };

  inherit rustPkgs-fenix;
  inherit (inputs) fenix;

  # Website stuff, small projects.
  website = {
    portfolio = rustPkgs.callPackage ./website/portfolio {};
    axum = rustPkgs-fenix.callPackage ./website/axum {
      inherit rustPlatform tabler-icons;
    };

    axum-login-test = rustPkgs.callPackage ./website/login-test {inherit tabler-icons;};
  };

  nx = config_dir: hostname: rustPkgs.callPackage ./nx-script {inherit config_dir hostname;};

  neovim-nix = let
    customPkgs = import inputs.nixpkgs-unstable {
      system = pkgs.stdenv.hostPlatform.system;
      config = {
        allowUnfree = true;
      };
      overlays = [
        inputs.nixneovimplugins.overlays.default
        neovim-plugins.overlay
      ];
    };
    nixvim = inputs.nixvim.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  in {
    default = nixvim.makeNixvimWithModule {
      pkgs = customPkgs;
      extraSpecialArgs = {inherit color-lib theme;};
      module = {
        imports = [./neovim/configurations/minimal.nix];
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

        # Generate completions using complgen
        echo "Generating completions for ${name}..."
        ${pkgs.complgen}/bin/complgen grammar.usage --bash $out/share/bash-completion/completions/${name}
        ${pkgs.complgen}/bin/complgen grammar.usage --fish $out/share/fish/vendor_completions.d/${name}.fish
        ${pkgs.complgen}/bin/complgen grammar.usage --zsh $out/share/zsh/site-functions/_${name}

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

  coffee-widget = pkgs.callPackage ./noctalia/coffee-widget {};

  audio-recorder = pkgs.callPackage ./noctalia/audio-recorder {};
}
