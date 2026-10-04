{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:
rustPlatform.buildRustPackage rec {
  pname = "jegrep";
  version = "0.1.3";

  src = fetchFromGitHub {
    owner = "can1357";
    repo = "jegrep";
    rev = "v${version}";
    hash = "sha256-+7oil+jATT+cvWflfvx4A57q10OTlXMzx/jz+uY41EQ=";
  };

  cargoHash = "sha256-t1nldEiBq9VTYHoSKrR2QZWqbmo/S/acaJ5LXj1vlM8=";

  doCheck = false; # tests hit the network / need API keys

  meta = {
    description = "Semantic grep: find code by describing what you're looking for, powered by Jev";
    homepage = "https://github.com/can1357/jegrep";
    license = lib.licenses.mit;
    mainProgram = "jegrep";
  };
}
