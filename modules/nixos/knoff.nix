{ inputs, self, outputs, theme, pkgs, ... }:
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager = {
    useGlobalPkgs = false;
    useUserPackages = true;
    users.knoff = import ../../home/knoff-laptop.nix;
    extraSpecialArgs = {
      inherit inputs outputs self theme;
      inherit (pkgs) system;
    };
  };
}
