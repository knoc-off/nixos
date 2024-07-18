{ pkgs, inputs, ... }: {
  website = {
    portfolio =
      pkgs.callPackage ./portfolio.nix { inherit (inputs) rust-overlay; };
  };
}
