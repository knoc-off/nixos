{ pkgs, shell ? false, ... }:

let
  package = pkgs.writeShellScriptBin "hello" ''
    echo "Hello, world!"
  '';

  shellDrv = pkgs.mkShell {
    buildInputs = [ package pkgs.cowsay ];
    shellHook = ''
      echo "Welcome to the example package shell!"
    '';
  };

in
  if shell then shellDrv else package
