{
  lib,
  pkgs,
  fetchFromGitea,
  cmake,
  ninja,
  git,
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

    # Allow network access during build to fetch clipper2
    # This is impure but keeps full functionality (MANIFOLD_CROSS_SECTION)
    __noChroot = true;

    cargoLock = {
      lockFile = ./Cargo.lock;
      outputHashes = {
        "debug-cell-0.1.1" = "sha256-EY6KE470jrl6sT2vUMaJ1cQYaHISZAXDgsDXyC4Ux9Q=";
      };
    };

    preConfigure = ''
      # Patch the vendored manifold-rs to respect CMAKE_GENERATOR env var
      for f in cargo-vendor-dir/manifold-rs-*/build.rs; do
        if [ -f "$f" ]; then
          echo "Patching $f to respect CMAKE_GENERATOR"
          sed -i 's/env::set_var("CMAKE_GENERATOR", "Ninja");/if env::var("CMAKE_GENERATOR").is_err() { env::set_var("CMAKE_GENERATOR", "Ninja"); }/' "$f"
        fi
      done
    '';

    nativeBuildInputs = [
      cmake
      ninja
      git
      pkgs.cacert
      pkgs.autoPatchelfHook
    ];

    buildInputs = [
      pkgs.stdenv.cc.cc.lib
    ];

    # Disable ninja hook - we want ninja available but not used for building
    dontUseNinjaBuild = true;
    dontUseNinjaInstall = true;

    # Override CMAKE_GENERATOR to use Unix Makefiles instead of Ninja
    # The patch allows this environment variable to be respected
    CMAKE_GENERATOR = "Unix Makefiles";

    # Set SSL certificates for git during cmake FetchContent
    SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

    meta = {
      description = "Modern programming language for CAD";
      homepage = "https://codeberg.org/microcad/microcad";
      license = lib.licenses.agpl3Only;
      maintainers = with lib.maintainers; [];
      mainProgram = "microcad";
    };
  }
