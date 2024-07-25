{ pkgs, inputs, ... }: {
  website = {
    portfolio = pkgs.callPackage ./portfolio.nix { inherit (inputs) rust-overlay; };
    backend = pkgs.callPackage ./backend.nix { inherit (inputs) rust-overlay; };
  };
}
