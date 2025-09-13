args: let
  home-manager =
    if args.lib.strings.hasSuffix "darwin" args.system
    then args.inputs.home-manager.darwinModules.home-manager
    else args.inputs.home-manager.nixosModules.home-manager;
in {
  imports = [
    home-manager
  ];

  home-manager.backupFileExtension = "bak";
  home-manager = {
    useGlobalPkgs = true; # does Disabling this have any benefits?
    useUserPackages = true;

    # this is the single-crossover point between nixos and home-manager
    users.${args.user} = {
      imports = [
        ../../home/${args.user}.nix

        # Could uncomment this if im not using global pkgs.
        # nixpkgs = {
        #   overlays = builtins.attrValues outputs.overlays;
        #   config = {
        #     allowUnfree = true;
        #     allowUnfreePredicate = _pkg: true;
        #   };
        # };

        #{ # TODO !!!!!!! FIXME
        # # If darwin, then User/${args.user} otherwise /home/${args.user}
        #  home = {
        #    username = "${args.user}";
        #    homeDirectory = "/home/${args.user}";
        #  };
        #}
      ];
    };

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
