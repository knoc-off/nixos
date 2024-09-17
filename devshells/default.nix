{ pkgs, inputs, ... }: {
  website = {
    portfolio = pkgs.callPackage ./portfolio.nix { inherit (inputs) rust-overlay; };
    backend = pkgs.callPackage ./backend.nix { inherit (inputs) rust-overlay; };
  };
  embeddedRust = pkgs.callPackage ./embeddedrust.nix { inherit (inputs) rust-overlay; };
  embedded-c = pkgs.callPackage ./embedded-c.nix { };
  #bevy-test = p
  bevy-test = rustPkgs.callPackage ./bevy-test/shell.nix { inherit rust-toolchain; };
}
