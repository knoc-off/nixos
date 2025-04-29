{ lib, inputs, pkgs, self, hostname, user, config, ... }@args: {
  programs.kodi = {

    enable = true;
    #package = pkgs.kodi-wayland;
    # package = # pkgs.kodi.withPackages (exts: [ exts.pvr-iptvsimple ]);
    package = pkgs.kodi-wayland.withPackages
      (kodiPkgs: with kodiPkgs; [ jellyfin youtube pvr-iptvsimple steam-controller ]);
    settings = { videolibrary.showemptytvshows = "true"; };
    sources = {
      video = {
        default = "movies";
        source = [
          # {
          #   name = "videos";
          #   path = "${config.home-manager.users.tv.xdg.userDirs.videos}/misc";
          #   allowsharing = "true";
          # }
          {
            name = "shows";
            path = "${config.xdg.dataHome}/shows";
            allowsharing = "true";
          }
          {
            name = "movies";
            path = "${config.xdg.dataHome}/movies";
            allowsharing = "true";
          }
        ];
      };
    };

  };

  home.stateVersion = "24.11";
}
