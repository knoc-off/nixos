{
        laptop-iso = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          system = "x86_64-linux";
          modules = [
            ./systems/framework13.nix
            ./systems/modules/live-iso.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = false;
                useUserPackages = true;
                users.knoff = import ./home/knoff-laptop.nix;
                extraSpecialArgs = {
                  inherit inputs outputs theme;
                  system = "x86_64-linux";
                };
              };
            }

          ];
        };
}
