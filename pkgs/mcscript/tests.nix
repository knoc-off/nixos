{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  pkgs ? import <nixpkgs> {},
}:
pkgs.stdenv.mkDerivation rec {
  pname = "mcscript";
  version = "0.2.3";

  src = fetchFromGitHub {
    owner = "Stevertus";
    repo = "mcscript";
    rev = version;
    hash = "sha256-+eC+UtJhnBao5nsytRROW+s4K3E1hG+n8QJpkN8ZaH8=";
  };

  buildInputs = [
    pkgs.nodejs
  ];

  installPhase = ''
    mkdir -p $out/bin
    cp -r ./bin $out/bin
    cp ./lib/* $out/lib
    chmod +x $out/bin/*
    substituteInPlace $out/bin/test-module.js \
      --replace "\"./lib/index.js\"" "\"${pkgs.nodejs}/lib/node_modules/mcscript/lib/index.js\""
    substituteInPlace $out/bin/watch.js \
      --replace "\"./lib/index.js\"" "\"${pkgs.nodejs}/lib/node_modules/mcscript/lib/index.js\""
    substituteInPlace $out/bin/modal.js \
      --replace "\"./lib/index.js\"" "\"${pkgs.nodejs}/lib/node_modules/mcscript/lib/index.js\""
    substituteInPlace $out/bin/add.js \
      --replace "\"./add.js\"" "\"${pkgs.nodejs}/lib/node_modules/mcscript/bin/add.js\""
  '';
}
