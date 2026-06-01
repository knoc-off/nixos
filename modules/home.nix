{ inputs, ... }: {
  nixos = {user, ...} @ args: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
    ];

    home-manager.backupFileExtension = "bak";
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;

      users.${user} = {
        imports = [
          ../home/${user}.nix

          {
            home = {
              username = "${user}";
              homeDirectory = "/home/${user}";
            };
          }
        ];
      };

      extraSpecialArgs = removeAttrs args [
        "config"
        "lib"
        "pkgs"
        "_module"
        "options"
      ];
    };
  };
}
