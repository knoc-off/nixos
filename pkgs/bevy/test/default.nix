{ pkgs ? import <nixpkgs> { }, additionalBuildInputs ? [ ] }:

with pkgs;

mkShell rec {
  nativeBuildInputs = [
    pkg-config
    mold
    clang
    rustc
    cargo
    rustfmt
    rust-analyzer
    clippy
  ];

  buildInputs = [
    udev
    alsa-lib
    vulkan-loader
    libGL

    # X11 dependencies
    xorg.libX11
    xorg.libXcursor
    xorg.libXrandr
    xorg.libXi

    # Wayland dependencies
    libxkbcommon
    wayland
  ] ++ additionalBuildInputs;

  LD_LIBRARY_PATH = lib.makeLibraryPath buildInputs;
}
