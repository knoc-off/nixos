{
  lib,
  pkgs,
  fenix,
}: let
  rustPlatform = pkgs.makeRustPlatform {
    cargo = fenix.minimal.toolchain;
    rustc = fenix.minimal.toolchain;
  };
in
  rustPlatform.buildRustPackage {
    pname = "recipt-printer";
    version = "0.1.0";
    src = ./.;

    cargoLock = {
      lockFile = ./Cargo.lock;
    };

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
    ];

    buildInputs = with pkgs; [
      systemd # provides libudev
    ];

    # Fix runtime library paths
    postInstall = ''
      wrapProgram $out/bin/recipt-printer \
        --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath [pkgs.systemd]}"
    '';

    # doCheck = false;

    meta = {
      description = "ESP32-C3 train time display";
      license = lib.licenses.mit;
      maintainers = [];
      platforms = lib.platforms.all;
    };
  }
