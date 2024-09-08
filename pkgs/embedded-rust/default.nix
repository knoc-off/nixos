{ pkgs, rustPlatform, rust-bin }:

let
  # Define the target platform (AVR)
  avrLibc = pkgs.pkgsCross.avr.libcCross;
  avrGcc = pkgs.pkgsCross.avr.buildPackages.gcc;

  # Use a nightly Rust toolchain with AVR support
  rustToolchain = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
    extensions = [ "rust-src" ];
    targets = [ "avr-unknown-gnu-atmega328" ];
  });
in

rustPlatform.buildRustPackage rec {
  pname = "arduino-rust-blink";
  version = "0.1.0";

  src = ./.;

  cargoLock.lockFile = ./Cargo.lock;
  cargoLock.outputHashes = {
     "arduino-hal-0.1.0" = "sha256-aC7XgHITGWGWpCSVaqLz6lXHQGWgiK24IPs20bK4DyQ=";
   };
  nativeBuildInputs = with pkgs; [
    pkg-config
    ravedude
    avrdude
    avrLibc
    avrGcc
    rustToolchain
  ];

  buildInputs = [ ];

  buildType = "release";

  checkPhase = "";

  preBuild = ''
    export CARGO_HOME=$(mktemp -d)
    export PATH=$CARGO_HOME/bin:$PATH
    export AVR_CPU_FREQUENCY_HZ=16000000
  '';

  buildPhase = ''
    export RUSTFLAGS="-C link-arg=-nostartfiles -C link-arg=-Wl,--gc-sections"
    cargo build --release --target avr-atmega328p-none-eabi
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp target/avr-atmega328p-none-eabi/release/${pname}.elf $out/bin/
  '';

  meta = with pkgs.lib; {
    description = "Rust-based LED blinker for Arduino Uno";
    homepage = "https://github.com/yourusername/arduino-rust-blink";
    license = licenses.mit;
    maintainers = with maintainers; [ yourusername ];
  };
}
