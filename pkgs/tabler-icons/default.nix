{ pkgs, lib }:

pkgs.stdenv.mkDerivation rec {
  pname = "tabler-icons";
  version = "3.29.0";

  src = pkgs.fetchFromGitHub {
    owner = "tabler";
    repo = "tabler-icons";
    rev = "v${version}";
    sha256 = "sha256-pSfCIc1nqi9EI+YM9NgUjs1wtmrc2uf7iWjwQunejkY=";
  };

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/icons
    cp -r icons/ $out/share/

    runHook postInstall
  '';

  meta = with lib; {
    description = "A set of free MIT-licensed high-quality SVG icons";
    homepage = "https://tabler-icons.io";
    license = licenses.mit;
    platforms = platforms.all;
    maintainers = [ knoff ];
  };
}
