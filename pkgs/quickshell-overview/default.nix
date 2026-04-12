{
  lib,
  stdenv,
  fetchFromGitHub,
}:

stdenv.mkDerivation {
  pname = "quickshell-overview";
  version = "unstable-2026-04-06";

  src = fetchFromGitHub {
    owner = "Shanu-Kumawat";
    repo = "quickshell-overview";
    rev = "25b83f7a372c58a42ced47a120ed75a561b60098";
    hash = "sha256-kBsfYgfksMPk4UqvBhyYX6HCWspD5x8uuN4ynn2/tPU=";
  };

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    dst=$out/share/quickshell-overview
    mkdir -p $dst
    cp shell.qml $dst/
    cp config.example.json $dst/
    cp -r common $dst/
    cp -r modules $dst/
    cp -r services $dst/
    runHook postInstall
  '';

  meta = {
    description = "Standalone workspace overview for Hyprland using Quickshell";
    homepage = "https://github.com/Shanu-Kumawat/quickshell-overview";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
