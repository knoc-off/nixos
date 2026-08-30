# Pannellum - lightweight standalone panorama viewer for the web
# https://pannellum.org / https://github.com/mpetroff/pannellum
{
  lib,
  stdenv,
  fetchzip,
  python3,
  makeWrapper,
}:
let
  version = "2.5.7";

  viewer = fetchzip {
    url = "https://github.com/mpetroff/pannellum/releases/download/${version}/pannellum-${version}.zip";
    hash = "sha256-QISwc8rB2ArHhMZiljMkBdU2axLCgp2q2HBo1tf0EXA=";
  };
in
stdenv.mkDerivation {
  pname = "pannellum";
  inherit version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/pannellum $out/bin
    install -m644 ${viewer}/pannellum.htm $out/share/pannellum/
    install -m644 ${viewer}/pannellum.js $out/share/pannellum/
    install -m644 ${viewer}/pannellum.css $out/share/pannellum/
    cp ${./pannellum-view.py} $out/bin/.pannellum-view.py

    makeWrapper ${python3}/bin/python3 $out/bin/pannellum-view \
      --add-flags "$out/bin/.pannellum-view.py" \
      --set PANNELLUM_SHARE "$out/share/pannellum"

    runHook postInstall
  '';

  meta = {
    description = "Lightweight standalone viewer for 360° equirectangular panoramas, opened in your browser";
    homepage = "https://pannellum.org";
    changelog = "https://github.com/mpetroff/pannellum/blob/${version}/changelog.md";
    license = lib.licenses.mit;
    mainProgram = "pannellum-view";
    platforms = lib.platforms.all;
  };
}
