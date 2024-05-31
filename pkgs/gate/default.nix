{ lib
, buildGoModule
, fetchFromGitHub
}:

buildGoModule rec {
  pname = "gate";
  version = "0.36.7";

  src = fetchFromGitHub {
    owner = "minekube";
    repo = "gate";
    rev = "v${version}";
    hash = "sha256-WHxpx20O/HuCWqbY4zTxcjyIhW3+FQtTz5sUGAda71g=";
  };

  vendorHash = "sha256-dswNJQWqN+u/mnpbj9se2j9uEi0ewNTXVlN3WnNbcyg=";

  ldflags = [ "-s" "-w" ];

  meta = with lib; {
    description = "High-Performance, Low-Memory, Lightweight, Extensible Minecraft Reverse Proxy with Excellent Multi-Protocol Version Support - Velocity/Bungee Replacement - Ready for dev and large deploy";
    homepage = "https://github.com/minekube/gate";
    license = licenses.asl20;
    maintainers = with maintainers; [ ];
    mainProgram = "gate";
  };
}
