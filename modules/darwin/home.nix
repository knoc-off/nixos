{user, ...} @ args: let
in {
  imports = [
    args.inputs.home-manager.darwinModules.home-manager
  ];

  home-manager.backupFileExtension = "bak";
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;

    # this is the single-crossover point between nixos and home-manager
    users.${user} = {
      imports = [
        ../../home/${user}.nix

        {
          home = {
            username = "${user}";
            # homeDirectory = "/Users/${user}"; # might not need to be specified?
          };
        }
      ];
    };

    # This could end badly. recursion, etc. yet i kinda like it.
    # Basically, this passes All arguments passed to this function into home-manager.
    # this is kinda a foot-gun, but if in doubt add below to filter out.
    extraSpecialArgs = removeAttrs args [
      "config" # NixOS system config
      "lib" # NixOS lib
      "pkgs" # Already available in home-manager
      "_module" # Internal NixOS module system stuff
      "options" # NixOS options
    ];
  };
}
