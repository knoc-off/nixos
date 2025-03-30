{ lib
, rustPlatform
, makeWrapper
, pkg-config
, openssl
}:

rustPlatform.buildRustPackage rec {
  pname = "nx";
  version = "0.1.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    openssl
  ];

  meta = with lib; {
    description = "NixOS configuration management tool";
    license = licenses.mit;
    maintainers = with maintainers; [ knoff ];
  };
}
