{pkgs, ...}:
{
  # this project spans a few different files. namely
  # nixos/pkgs/spotify-adblock/default.nix
  # nixos/overlays/default.nix
  # nixos/home/programs/media/audio/spotify.nix
  # i would like to consolidate these into one, at some point.
  home.packages = with pkgs; [
    spotiblock # my custom package defined at nixos/pkgs/spotify-adblock
  ];
  # installs the needed files for the adblocker.
  home.file.".config/spotify-adblock/config.toml" = {
    enable = true;
    source  = "${pkgs.spotify-adblock}/config.toml";
    target = ".config/spotify-adblock/config.toml";
  };

}
