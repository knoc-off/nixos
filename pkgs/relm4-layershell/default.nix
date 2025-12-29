{
  lib,
  pkgs,
  rustPlatform,
}:
rustPlatform.buildRustPackage rec {
  pname = "relm-layershell";
  version = "0.8.5";
  src = ./.;
  cargoHash = "sha256-dQD0TceZQvIedxLXpnQwupYgr54NxUBx+cHNY6v13Jo=";
  cargoAuditable = null;

  nativeBuildInputs = [
    pkgs.gcc
    pkgs.pkg-config
  ];

  buildInputs = with pkgs; [
    openssl
    openssl.dev
    zlib.dev
    libxkbcommon
    wayland
    libGL
    mesa
    gtk4
    gtk4-layer-shell
    glib
    cairo
    pango
    gdk-pixbuf
    graphene
  ];
  LD_LIBRARY_PATH = lib.makeLibraryPath [
    pkgs.openssl
    pkgs.libxkbcommon
    pkgs.wayland
    pkgs.libGL
    pkgs.mesa
    pkgs.gtk4
    pkgs.gtk4-layer-shell
    pkgs.glib
    pkgs.cairo
    pkgs.pango
    pkgs.gdk-pixbuf
    pkgs.graphene
  ];

  meta = {
    description = "";
    homepage = "https://github.com/shshemi/tabiew";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [];
    mainProgram = "relm-layershell";
  };
}
