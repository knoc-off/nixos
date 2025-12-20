{
  lib,
  pkgs,
  fetchFromGitea,
  cmake,
  ninja,
  git,
  clipper2,
  pkg-config,
  fenix,
}: let
  rustPlatform = pkgs.makeRustPlatform {
    cargo = fenix.minimal.toolchain;
    rustc = fenix.minimal.toolchain;
  };
in
  rustPlatform.buildRustPackage rec {
    pname = "microcad";
    version = "0.2.18";

    src = fetchFromGitea {
      domain = "codeberg.org";
      owner = "microcad";
      repo = "microcad";
      rev = "v${version}";
      hash = "sha256-FNjGXYUui50S2BTutRQlLljo6afsTeDQ5cxtobxlJy4=";
      fetchSubmodules = true;
    };

    cargoLock = {
      lockFile = ./Cargo.lock;
      outputHashes = {
        "debug-cell-0.1.1" = "sha256-EY6KE470jrl6sT2vUMaJ1cQYaHISZAXDgsDXyC4Ux9Q=";
      };
    };

    preBuild = ''
      # Patch the vendored manifold-rs to respect CMAKE_GENERATOR env var
      # and use system clipper2 instead of downloading it
      echo "Looking for manifold-rs build.rs files in cargo-vendor-dir..."
      ls -la cargo-vendor-dir/ | head -20 || true

      for f in cargo-vendor-dir/manifold-rs-*/build.rs; do
        if [ -f "$f" ]; then
          echo "Found and patching $f"
          echo "Before patch:"
          grep -n "CMAKE_GENERATOR\|BUILTIN_CLIPPER2" "$f" || true

          sed -i 's/env::set_var("CMAKE_GENERATOR", "Ninja");/if env::var("CMAKE_GENERATOR").is_err() { env::set_var("CMAKE_GENERATOR", "Ninja"); }/' "$f"
          sed -i 's/\.define("MANIFOLD_USE_BUILTIN_CLIPPER2", "ON")/\.define("MANIFOLD_USE_BUILTIN_CLIPPER2", "OFF")/' "$f"

          echo "After patch:"
          grep -n "CMAKE_GENERATOR\|BUILTIN_CLIPPER2" "$f" || true
        fi
      done
      echo "Done patching."
    '';

    nativeBuildInputs = [
      cmake
      ninja
      pkg-config
      pkgs.autoPatchelfHook
    ];

    buildInputs = [
      pkgs.stdenv.cc.cc.lib
      clipper2
    ];

    # Disable ninja hook - we want ninja available but not used for building
    dontUseNinjaBuild = true;
    dontUseNinjaInstall = true;

    # Override CMAKE_GENERATOR to use Unix Makefiles instead of Ninja
    # The patch allows this environment variable to be respected
    CMAKE_GENERATOR = "Unix Makefiles";

    # Help cmake find clipper2
    CMAKE_PREFIX_PATH = "${clipper2}";
    Clipper2_DIR = "${clipper2}/lib/cmake/clipper2";
    PKG_CONFIG_PATH = "${clipper2}/lib/pkgconfig";

    meta = {
      description = "Modern programming language for CAD";
      homepage = "https://codeberg.org/microcad/microcad";
      license = lib.licenses.agpl3Only;
      maintainers = with lib.maintainers; [];
      mainProgram = "microcad";
    };
  }
