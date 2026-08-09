# A minimal, couch-navigable file browser: a Quickshell layer-shell overlay
# with a places sidebar and a FolderListModel-backed grid, all keyboard/D-pad
# driven (no mouse, no terminal). Theme.qml (base16 colors + places) is
# generated and deployed separately by modules/tv-files.nix, alongside the
# static QML shipped here -- see that module for why the split.
{
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "tv-files";
  version = "0.1.0";

  src = ./.;

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall
    dst=$out/share/tv-files
    mkdir -p $dst
    cp shell.qml $dst/
    cp -r modules $dst/
    cp -r services $dst/
    runHook postInstall
  '';

  meta = {
    description = "Couch-navigable Quickshell file browser for the TV";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
