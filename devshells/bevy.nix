{ pkgs }:
pkgs.mkShell rec {
  nativeBuildInputs = with pkgs; [
    pkg-config

    mold-wrapped
    clang_16

    rust-toolchain

    (pkgs.hiPrio pkgs.bashInteractive)
  ];

  buildInputs = with pkgs; [
    udev
    alsa-lib
    vulkan-loader

    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr

    libxkbcommon
    wayland
  ];

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;

  RUST_SRC_PATH = "${pkgs}/lib/rustlib/src/rust/library";
}
