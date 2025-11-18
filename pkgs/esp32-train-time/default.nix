{
  lib,
  pkgs,
  fenix,
}:
let
  # Build ESP32-C3 toolchain with RISC-V target and rust-src for build-std
  espToolchain = fenix.combine [
    fenix.stable.rustc
    fenix.stable.cargo
    fenix.stable.rust-src
    fenix.targets.riscv32imc-unknown-none-elf.stable.rust-std
  ];

  rustPlatform = pkgs.makeRustPlatform {
    cargo = espToolchain;
    rustc = espToolchain;
  };
in
rustPlatform.buildRustPackage rec {
  pname = "esp32-train-time";
  version = "0.1.0";
  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  buildPhase = ''
    runHook preBuild

    export RUSTFLAGS="-C link-arg=-Tlinkall.x"
    cargo build --release --target riscv32imc-unknown-none-elf

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp target/riscv32imc-unknown-none-elf/release/${pname} $out/bin/ 2>/dev/null || \
    cp target/riscv32imc-unknown-none-elf/release/${pname}.elf $out/bin/${pname} 2>/dev/null || \
    find target/riscv32imc-unknown-none-elf/release -maxdepth 1 -type f ! -name "*.d" ! -name "*.rlib" -executable -exec cp {} $out/bin/ \;

    runHook postInstall
  '';

  doCheck = false;

  # Disable cargo-auditable - linker doesn't support the flags
  auditable = false;

  meta = {
    description = "ESP32-C3 train time display";
    license = lib.licenses.mit;
    maintainers = [];
    platforms = lib.platforms.all;
  };
}
