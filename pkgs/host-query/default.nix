{ lib, stdenv, python3, systemd, makeWrapper }:

stdenv.mkDerivation {
  pname = "host-query";
  version = "0.1.0";

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/host-query/plugin $out/bin

    cp ${./server.py} $out/lib/host-query/server.py
    cp ${./opencode-plugin.js} $out/lib/host-query/plugin/index.js

    makeWrapper ${python3}/bin/python3 $out/bin/host-query \
      --add-flags "$out/lib/host-query/server.py" \
      --prefix PATH : ${lib.makeBinPath [ systemd ]}

    runHook postInstall
  '';

  meta = {
    description = "Host query service for jailed opencode agents";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "host-query";
  };
}
