{
  lib,
  python3Packages,
  fetchFromGitHub,
}:
python3Packages.buildPythonApplication rec {
  pname = "hyprkan";
  version = "2.2.0";
  format = "other";

  src = fetchFromGitHub {
    owner = "haithium";
    repo = "hyprkan";
    rev = "v${version}";
    hash = "sha256-4J0yQSkFTbHTDFBXECbCs/43xTDbeB/f3J7tZIbjbwM=";
  };

  propagatedBuildInputs = with python3Packages; [
    xlib
    i3ipc
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m755 src/hyprkan.py $out/bin/hyprkan

    runHook postInstall
  '';

  meta = {
    description = "App-aware Kanata layer switcher for Linux";
    homepage = "https://github.com/haithium/hyprkan";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [];
    mainProgram = "hyprkan";
    platforms = lib.platforms.linux;
  };
}
