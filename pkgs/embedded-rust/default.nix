{ pkgs }:

let
  inherit (pkgs) rust-bin;
in

pkgs.stdenv.mkDerivation rec {
  pname = "arduino-rust-blink";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = with pkgs; [
    cargo-edit
    cargo-generate
    (rust-bin.nightly.latest.default.override {
      extensions = ["rust-src"];
      targets = ["x86_64-unknown-linux-gnu"];
    })
    rust-analyzer
    sccache
    pkg-config
    ravedude
    avrdude
  ];

  buildInputs = with pkgs.pkgsCross.avr; [
    gcc
  ];

  buildPhase = ''
    export CARGO_HOME=$(mktemp -d)
    cargo build --release
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp release/arduino-rust-blink $out/bin/
  '';

  meta = with pkgs.lib; {
    description = "Rust-based LED blinker for Arduino Uno";
    homepage = "https://github.com/yourusername/arduino-rust-blink";
    license = licenses.mit;
    maintainers = with maintainers; [ yourusername ];
  };
}

