{ pkgs, rust-overlay }:

let
  # Use rust-overlay to get the Rust toolchain
  rust-toolchain = (pkgs.extend rust-overlay.overlays.default).rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
in
pkgs.mkShell rec {
  nativeBuildInputs = with pkgs; [
    # from https://github.com/bevyengine/bevy/blob/main/docs/linux_dependencies.md#Nix
    pkg-config

    # from https://bevyengine.org/learn/book/getting-started/setup/#enable-fast-compiles-optional
    mold-wrapped
    clang_16

    rust-toolchain

    # From https://github.com/dpc/htmx-sorta/blob/9e101583ec9391127b5bfcbe421e3ede2d627856/flake.nix#L83-L85
    # This is required to prevent a mangled bash shell in nix develop
    # see: https://discourse.nixos.org/t/interactive-bash-with-nix-develop-flake/15486
    (pkgs.hiPrio pkgs.bashInteractive)
  ];

  buildInputs = with pkgs; [
    # common bevy dependencies
    udev
    alsa-lib
    vulkan-loader

    # bevy x11 feature
    xorg.libX11
    xorg.libXcursor
    xorg.libXi
    xorg.libXrandr

    # bevy wayland feature
    libxkbcommon
    wayland

    # often this becomes necessary sooner or later
    # openssl
  ];

  # from bevy setup as well
  LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;

  # Some environment to make rust-analyzer work correctly (Still the path prefix issue)
  # See https://github.com/oxalica/rust-overlay/issues/129
  RUST_SRC_PATH = "${rust-toolchain}/lib/rustlib/src/rust/library";
}
