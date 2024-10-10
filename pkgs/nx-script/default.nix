{ lib
, rustPlatform
, makeWrapper
, pkg-config
, openssl
, config_dir
, hostname
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

  postInstall = ''
    wrapProgram $out/bin/nx \
      --set config_dir "${config_dir}" \
      --set hostname "${hostname}"
  '';

  meta = with lib; {
    description = "NixOS configuration management tool";
    homepage = "";
    license = licenses.mit;
    maintainers = with maintainers; [ knoff ];
  };
}
