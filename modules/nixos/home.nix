{ args, ... }: {
  imports = [ args.inputs.home-manager.nixosModules.home-manager ];

  home-manager.backupFileExtension = "bak";
  home-manager = {

    useGlobalPkgs = false;
    useUserPackages = true;

    # this is the single-crossover point between nixos and home-manager
    users.${args.user} = import ../../home/${args.user}.nix;

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
