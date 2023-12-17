#
{ stdenv , fetchFromGitHub , writeShellScript , sha256 }:
stdenv.mkDerivation rec {
  name = "themes-${version}";
  version = "0.1";

  builder = writeShellScript "builder.sh" ''
    echo "hi, my name is ''${0}" # escape bash variable
    echo "hi, my hash is ${sha256}" # use nix variable
    echo "hello world" >output.txt
  '';



 }
