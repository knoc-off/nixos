{ inputs, pkgs, ... }@args:
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager = {
    useGlobalPkgs = false;
    useUserPackages = true;
    users.knoff = import ../../home/knoff-laptop.nix;
    extraSpecialArgs = args // {
      inherit (pkgs) system;
    };
  };
}
