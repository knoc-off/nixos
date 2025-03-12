{ pkgs ? import <nixpkgs> { } }:

let
  pythonEnv = pkgs.python312.withPackages (ps:
    with ps; [
      # Core dependencies
      python-dotenv
      sqlite-utils
      requests

    ]);

in pkgs.mkShell {
  buildInputs = with pkgs; [ pythonEnv poetry sqlite sqlx-cli ];

  shellHook = ''
    source .env
  '';
}
