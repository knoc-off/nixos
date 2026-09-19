{
  lib,
  stdenv,
  python3,
  systemd,
  bindfs,
  openssh-askpass,
  makeWrapper,
}:

stdenv.mkDerivation {
  pname = "host-query";
  version = "0.1.0";

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/host-query/plugin $out/bin $out/libexec

    cp ${./server.py} $out/lib/host-query/server.py
    cp ${./opencode-plugin.js} $out/lib/host-query/plugin/index.js

    # bindfs backs the directory grants (POST /mount) -- FUSE so it needs no
    # root, unlike `mount --bind`.
    #
    # The askpass helper is how sudo asks for a password once commands run
    # without a terminal: a GTK dialog on the user's desktop rather than a
    # prompt smeared across the agent's TUI. Wrapped to clear LD_LIBRARY_PATH
    # because host commands inherit this server's environment, and a dev shell
    # (direnv, nix develop) leaks library paths that make GTK abort on a symbol
    # lookup before the window ever appears.
    makeWrapper ${openssh-askpass}/libexec/gtk-ssh-askpass $out/libexec/host-query-askpass \
      --unset LD_LIBRARY_PATH

    makeWrapper ${python3}/bin/python3 $out/bin/host-query \
      --add-flags "$out/lib/host-query/server.py" \
      --set HOST_QUERY_ASKPASS "$out/libexec/host-query-askpass" \
      --prefix PATH : ${
        lib.makeBinPath [
          systemd
          bindfs
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Host query service for jailed opencode agents";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "host-query";
  };
}
