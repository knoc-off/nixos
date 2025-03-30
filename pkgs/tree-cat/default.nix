{ lib
, rustPlatform
, makeWrapper
, pkg-config
, openssl
, tree-sitter
, stdenv
, tree-sitter-grammars
, pkgs
}:

pkgs.rustPlatform.buildRustPackage rec {
  pname = "tree-cat";
  version = "0.1.0";

  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    tree-sitter
    tree-sitter-grammars.tree-sitter-rust
    stdenv.cc
  ];


  buildInputs = [
    openssl
    tree-sitter
    tree-sitter-grammars.tree-sitter-rust
  ];

  meta = with lib; {
    description = "NixOS configuration management tool";
    license = licenses.mit;
    maintainers = with maintainers; [ knoff ];
  };
}
