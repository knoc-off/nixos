{ pkgs, lib, stdenv, rustPlatform, ... }:

let
  #rustPkgs = pkgs.extend (import rust-overlay);
  avrLibc = pkgs.pkgsCross.avr.libcCross;
  avrTarget = "avr-unknown-gnu-atmega328";
in rustPlatform.buildRustPackage rec {
  pname = "arduino-rust-project";
  version = "0.1.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "arduino-hal-0.1.0" =
        "sha256-xoWxvOcP9CAB+Ctl5xcKtOIa0GJSu4Lk4eg9+x9E4Rc=";
    };
  };

  nativeBuildInputs = with pkgs; [
    (rust-bin.nightly.latest.default.override {
      extensions = [ "rust-src" ];
      #targets = ["avr-unknown-gnu-atmega328"];
    })
    cargo-edit
    cargo-generate
    rust-analyzer
      #cargo-xbuild
    sccache
    pkg-config
    ravedude
    avrdude
  ];

  buildInputs = [ avrLibc pkgs.pkgsCross.avr.buildPackages.gcc ];

  CARGO_BUILD_TARGET = "avr-unknown-gnu-atmega328";

  preBuild = ''
    export RUST_TARGET_PATH="$(pwd)"
    export LIBAVR_DIR="${avrLibc}/avr"
    export RUSTFLAGS="-C target-cpu=atmega328p"
  '';

  buildPhase = ''
    runHook preBuild
    cargo build --release --target ${avrTarget} -Z build-std=core,alloc -Z build-std-features=compiler-builtins-mem
    runHook postBuild
  '';

  checkPhase = ''
    runHook preCheck
    cargo test --target ${avrTarget} -Z build-std=core
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp target/${avrTarget}/release/${pname} $out/bin/
    runHook postInstall
  '';

  #postBuild = ''
  #  avr-strip target/avr-unknown-gnu-atmega328/release/${pname}
  #'';

  #cargoTestCommands = x: x ++ ["--target ${CARGO_BUILD_TARGET}"];

  meta = with lib; {
    description = "A Rust project for Arduino";
    homepage = "https://github.com/yourusername/arduino-rust-project";
    license = licenses.mit;
    maintainers = with maintainers; [ yourusername ];
  };
}
