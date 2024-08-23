{ inputs, outputs, theme, self, pkgs, ... }:
{
  knoff = import ./knoff.nix { inherit inputs outputs self theme pkgs; };
}
