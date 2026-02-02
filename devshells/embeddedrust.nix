{ pkgs, rust-overlay }: let
  rustPkgs = pkgs.extend (import rust-overlay);
in
  pkgs.mkShell {
    nativeBuildInputs = with rustPkgs; [
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

      pkgsCross.avr.buildPackages.gcc
    ];


    RUST_BACKTRACE = 1;
  }

