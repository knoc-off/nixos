{lib ? import <nixpkgs/lib>}: {
  color-lib = import ./color-lib/color-manipulation.nix {inherit lib;};
  math = import ./math.nix {inherit lib;};
}
