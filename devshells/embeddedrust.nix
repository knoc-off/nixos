{ lib
, pkgs
, rust-bin
, avr-gcc
, avr-libc
, avrdude
}:

let
  # Select the latest nightly Rust toolchain with rust-src and AVR target
  rustToolchain = rust-bin.selectLatestNightlyWith (toolchain: toolchain.default.override {
    extensions = [ "rust-src" ];
    targets = [ "avr-unknown-gnu-atmega328" ];
  });

  # Create a custom AVR Rust toolchain
  avrRustToolchain = rustToolchain.override {
    targets = [ "avr-unknown-gnu-atmega328" ];
  };

  # Define the AVR GCC toolchain
  avrGccToolchain = pkgs.pkgsCross.avr.buildPackages.gcc;

in pkgs.mkShell {
  nativeBuildInputs = with pkgs; [
    # Rust toolchain
    avrRustToolchain

    # AVR tools
    avr-gcc
    avr-libc
    avrdude

    # Additional tools
    pkg-config
    openssl
    cmake
  ];

  buildInputs = with pkgs; [
    # Any additional libraries or dependencies
  ];

  # Environment variables
  RUST_BACKTRACE = 1;
  RUST_SRC_PATH = "${avrRustToolchain}/lib/rustlib/src/rust/library";
  AVR_CPU_FREQUENCY_HZ = "16000000";  # Adjust based on your microcontroller

  # Rust-specific environment variables
  RUSTFLAGS = "-C target-cpu=atmega328p";
  CARGO_TARGET_AVR_UNKNOWN_GNU_ATMEGA328_RUSTFLAGS = "-C link-arg=-Wl,--gc-sections";

  # AVR GCC environment variables
  CC_avr_unknown_gnu_atmega328 = "${avrGccToolchain}/bin/avr-gcc";
  AR_avr_unknown_gnu_atmega328 = "${avrGccToolchain}/bin/avr-ar";

  shellHook = ''
    echo "Embedded Rust development environment loaded"
    echo "Rust toolchain: $(rustc --version)"
    echo "AVR GCC: $(${avrGccToolchain}/bin/avr-gcc --version | head -n1)"
    echo "AVR Libc: ${avr-libc.version}"
    echo "AVRDude: $(avrdude -v 2>&1 | head -n1)"
    echo ""
    echo "To compile for AVR, use:"
    echo "cargo build --target avr-unknown-gnu-atmega328"
  '';
}
