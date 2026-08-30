# rhizome — Trilium notes in Neovim.
#
# Two outputs from one source tree:
#   - `rhizome`        the Rust engine (ETAPI, segmentation, conversion, splice)
#   - `passthru.plugin` the Neovim plugin, wrapped so it finds that binary
#
# Discovered automatically as `packages.<system>.rhizome` by `discoverPackages`.
{
  lib,
  pkgs,
  ...
}:
let
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
  version = cargoToml.workspace.package.version;

  rhizome = pkgs.rustPlatform.buildRustPackage {
    pname = "rhizome";
    inherit version;

    src = lib.cleanSourceWith {
      src = ./.;
      filter =
        path: type:
        let
          base = baseNameOf path;
        in
        !(builtins.elem base [
          ".cargo-home"
          "target"
          ".direnv"
        ])
        && lib.cleanSourceFilter path type;
    };

    cargoLock.lockFile = ./Cargo.lock;

    cargoBuildFlags = [
      "-p"
      "rhizomed"
    ];
    cargoTestFlags = [ "--workspace" ];

    # reqwest is built against rustls, so no system OpenSSL is needed.
    nativeBuildInputs = [ pkgs.pkg-config ];

    meta = {
      description = "Trilium notes as Neovim buffers, with lossless-by-proof HTML round-tripping";
      license = lib.licenses.mit;
      mainProgram = "rhizome";
    };
  };

  # The Lua side. `bin` is baked in so the plugin never depends on the binary
  # being on $PATH.
  plugin = pkgs.vimUtils.buildVimPlugin {
    pname = "rhizome-nvim";
    inherit version;
    src = lib.cleanSourceWith {
      src = ./.;
      filter =
        path: _:
        let
          rel = lib.removePrefix (toString ./. + "/") (toString path);
        in
        lib.hasPrefix "lua" rel || lib.hasPrefix "plugin" rel;
    };
    postInstall = ''
      substituteInPlace $out/lua/rhizome/init.lua \
        --replace-fail 'bin = "rhizome"' 'bin = "${lib.getExe rhizome}"'
    '';
    # date.lua has no `vim` dependency, so its date arithmetic (the noon
    # anchoring that keeps "today" from flipping to tomorrow after local
    # noon, and from drifting across DST transitions) is checked directly
    # with a plain `lua` interpreter rather than a Neovim test harness.
    doCheck = true;
    nativeCheckInputs = [ pkgs.lua ];
    checkPhase = ''
      runHook preCheck
      TZ=Europe/Berlin TZDIR=${pkgs.tzdata}/share/zoneinfo LUA_PATH="$PWD/lua/?.lua;;" \
        lua ${./tests/date.lua}
      runHook postCheck
    '';
    meta.description = "Neovim client for Trilium notes over ETAPI";
  };
in
rhizome
// {
  passthru = (rhizome.passthru or { }) // {
    inherit plugin;

    devShell = pkgs.mkShell {
      inputsFrom = [ rhizome ];
      nativeBuildInputs = [
        pkgs.cargo
        pkgs.rustc
        pkgs.clippy
        pkgs.rustfmt
        pkgs.rust-analyzer
        # `spike` and `check` are run against real note HTML; pandoc is here
        # only to re-derive the comparison numbers in the README.
        pkgs.pandoc
        pkgs.jq
      ];
      shellHook = ''
        echo "rhizome dev shell"
        echo "  cargo test --workspace"
        echo "  cargo run -p rhizomed -- spike <dir-of-note-html>"
      '';
    };
  };
}
