{ pkgs, inputs, system, ... }: {

   spotify-adblock = pkgs.callPackage ./spotify-adblock {};
   llm-cmd = pkgs.python3Packages.callPackage ./llm-cmd {};
   ttok = pkgs.python3Packages.callPackage ./ttok {};
   poe = pkgs.python3Packages.callPackage ./poe-llm-api {};
   gate = pkgs.callPackage ./gate {};
   ascii-silhouettify = pkgs.callPackage ./ascii {};

  neovim =
  let
    nixvim = inputs.nixvim.legacyPackages.${system};


    customPkgs = import inputs.nixpkgs-unstable {
      inherit system;
      config = {
        allowUnfree = true;
      };
      overlays = [
        #(import inputs.nixneovimplugins.overlays.default)
      ];
    };

  in
  {
    default =
      nixvim.makeNixvimWithModule {
        pkgs = customPkgs;
        #pkgs = unstablePkgs;
        #inherit pkgs;
        module = import ./neovim/configurations;
      };
  };

   website =
   let
     #rust-overlay = inputs.rust-overlay;
     rustPkgs = pkgs.extend (import inputs.rust-overlay);
   in
   {
     portfolio = rustPkgs.callPackage ./portfolio { };
   };

   # This lets me use font glyphs as SVG's for places that dont accept SVG.
   material-icons-ext = import ./svg-tools/icon-extractor {inherit pkgs;
    fontPath = "${pkgs.material-icons}/share/fonts/opentype/MaterialIconsRound-Regular.otf";
   };

   writeNuScript =
     name:
       (script:
         pkgs.writeTextFile rec {
           inherit name;
           text = "#!${pkgs.nushell}/bin/nu" + "\n" + script;

           executable = true;
           destination = "/bin/${name}";
         }
       );
}
