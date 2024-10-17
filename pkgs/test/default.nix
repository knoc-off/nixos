{ pkgs, stdenv, lib, cowsay }:

stdenv.mkDerivation rec {
  pname = "hello-example";
  version = "1.0.0";

  src = ./.;

  buildInputs = [ cowsay ];

  buildPhase = ''
    mkdir -p $out/bin
    echo '#!/bin/sh' > $out/bin/hello
    echo 'echo "Hello, world!"' >> $out/bin/hello
    chmod +x $out/bin/hello
  '';

  installPhase = "true";

  shellHook = ''
    echo "Welcome to the example package shell!"
  '';

  meta = with lib; {
    description = "A simple hello world package";
    license = licenses.mit;
    platforms = platforms.all;
  };

  passthru.shell = pkgs.mkShell {
    inputsFrom = [ ];
    buildInputs = [ cowsay ];
  };
}
