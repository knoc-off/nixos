{ pkgs, rustPlatform, lib }:

rustPlatform.buildRustPackage rec {
  pname = "AOC24_1";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = with pkgs; [

    # for wrapping the binary
    makeWrapper
    patchelf

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

  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;

  patches = [ ./remove-dynamic-linking.patch ];

  postInstall = ''
    cp -r assets $out/bin/

    # link the fonts, ${pkgs.fira}/share/fonts/opentype/FiraCode-Regular.otf
    mkdir -p $out/bin/assets/fonts

    ln -s ${pkgs.fira}/share/fonts/opentype/FiraSans-Regular.otf \
      $out/bin/assets/fonts/FiraSans-Regular.otf

  '';

  postFixup = ''
    patchelf --set-rpath ${pkgs.lib.makeLibraryPath buildInputs} $out/bin/${pname}
  '';

    # Disables dynamic linking when building with Nix
  cargoBuildOptions = [ "--no-default-features" ];


  # Set the library path for Bevy's dependencies
  #export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath buildInputs}

  meta = with lib; {
    description = "A Bevy program built with Nix and rustPlatform";
    homepage = "https://example.com";
    license = licenses.mit;
    maintainers = with lib.maintainers; [ yourName ];
  };
}
