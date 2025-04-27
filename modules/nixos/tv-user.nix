{ inputs, user, pkgs, ... }@args: {
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager.backupFileExtension = "bak";
  home-manager = {
    useGlobalPkgs = false;
    useUserPackages = true;
    users.${user} = import ../home/knoff-laptop.nix;
    # This could end badly. recursion, etc. yet i kinda like it.
    extraSpecialArgs = removeAttrs args [
      "config" # NixOS system config
      "lib" # NixOS lib
      "pkgs" # Already available in home-manager
      "_module" # Internal NixOS module system stuff
      "options" # NixOS options
    ];
  };
}
