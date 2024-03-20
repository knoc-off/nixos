# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
{ pkgs, ... }: {

   #example = pkgs.callPackage ./example { };
   # i think its pkgs.additions.spotify-adblock?
   spotify-adblock = pkgs.callPackage ./spotify-adblock {};
}
