# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{ pkgs, ... }: {

   #example = pkgs.callPackage ./example { };
   # i think its pkgs.additions.spotify-adblock?
   spotify-adblock = pkgs.callPackage ./spotify-adblock {};
   volumeLerp = pkgs.callPackage ./system-interface/volume-lerp-rust {};


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
