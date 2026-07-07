{ lib, stdenv, python3, pipewire, makeWrapper }:
let
  py = python3.withPackages (ps: with ps; [ numpy scipy ]);
in
stdenv.mkDerivation {
  pname = "pa-sweep";
  version = "0.1.0";

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp ${./pa-sweep.py} $out/bin/.pa-sweep.py

    makeWrapper ${py}/bin/python3 $out/bin/pa-sweep \
      --add-flags "$out/bin/.pa-sweep.py" \
      --prefix PATH : ${lib.makeBinPath [ pipewire ]}

    runHook postInstall
  '';

  meta = {
    description = "One-off room-reading self-test: ESS sweep -> ring-frequency notch suggestions for pa-voice";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "pa-sweep";
  };
}
