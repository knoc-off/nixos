{ pkgs, rustPlatform, lib }:

rustPlatform.buildRustPackage rec {
  pname = "bevy-test";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [
    # Bevy dependencies
    pkg-config

    # For faster compiles
    mold-wrapped
    clang_16

    # Addressing shell issues (if needed)
    (pkgs.hiPrio pkgs.bashInteractive)
  ];

  buildInputs = with pkgs; [
    # Common Bevy dependencies
    udev
    alsa-lib
    vulkan-loader

    # Bevy
    pkg-config
    alsa-lib
    vulkan-tools
    vulkan-headers
    vulkan-loader
    vulkan-validation-layers
    udev
    clang
    lld

    # Bevy X11 feature
    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr

    # Bevy Wayland feature
    libxkbcommon
    wayland

    openssl
  ];

  shellHook = ''
    # Required
    #export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$ {
    #  pkgs.lib.makeLibraryPath [ pkgs.alsaLib pkgs.udev pkgs.vulkan-loader ]
    #}"
    export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath buildInputs}
  '';

  # Set the library path for Bevy's dependencies
  #export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath buildInputs}

  meta = with lib; {
    description = "A Bevy program built with Nix and rustPlatform";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with lib.maintainers; [ yourName ];
  };
}
