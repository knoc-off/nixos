{ pkgs, rustPlatform, lib }:

rustPlatform.buildRustPackage rec {
  pname = "your-package-name";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    openssl
  ];

  meta = with lib; {
    description = "A minimal Rust program built with Nix and rustPlatform";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with lib.maintainers; [ yourName ];
  };
}

