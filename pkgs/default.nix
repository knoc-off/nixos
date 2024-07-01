# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{ pkgs, inputs, ... }: {

   #example = pkgs.callPackage ./example { };
   # i think its pkgs.additions.spotify-adblock?
   spotify-adblock = pkgs.callPackage ./spotify-adblock {};
   #volumeLerp = pkgs.callPackage ./system-interface/volume-lerp-rust {};
   #llm-cmd = pkgs.callPackage ./llm-cmd.nix {};
   llm-cmd = pkgs.python3Packages.callPackage ./llm-cmd {};
   ttok = pkgs.python3Packages.callPackage ./ttok {};
   poe = pkgs.python3Packages.callPackage ./poe-llm-api {};
   gate = pkgs.callPackage ./gate {};
   ascii-silhouettify = pkgs.callPackage ./ascii {};
   #material-icons-ext = pkgs.callPackage ./material-icons-ext {};


    website =
    let
      #rust-overlay = inputs.rust-overlay;
      rustPkgs = pkgs.extend (import inputs.rust-overlay);
    in
    {
      portfolio = rustPkgs.callPackage ./portfolio { };
    };




   material-icons-ext = (import ./svg-tools/icon-extractor {inherit pkgs;
    fontPath = "${pkgs.material-design-icons}/share/fonts/truetype/materialdesignicons-webfont.ttf";
   } );



    writeNuScript =
      (name:
        (script:
          pkgs.writeTextFile rec {
            inherit name;
            text = ( "#!${pkgs.nushell}/bin/nu" + "\n" + script);

            executable = true;
            destination = "/bin/${name}";
          }
        )
      );
}
