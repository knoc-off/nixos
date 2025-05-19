{ lib, inputs, pkgs, self, hostname, user, config, ... }@args: {
  programs.kodi = {

    enable = true;
    #package = pkgs.kodi-wayland;
    # package = # pkgs.kodi.withPackages (exts: [ exts.pvr-iptvsimple ]);
    package = pkgs.kodi-wayland.withPackages (kodiPkgs:
      with kodiPkgs; [
        jellyfin
        youtube
        pvr-iptvsimple
        steam-controller
      ]);
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

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    # MOZ_ENABLE_WAYLAND = "1"; # For Firefox, if not already set elsewhere
    XDG_SESSION_TYPE = "wayland";
  };


  # # Override the generated systemd user services to ensure they use Wayland
  # systemd.user.services.kdeconnect = { # This targets the service for kdeconnectd
  #   Service.Environment = lib.mkOverride 90 [ # mkOverride with a priority
  #     # It's important to preserve any existing PATH set by the module,
  #     # or set a sensible default.
  #     # The default HM module sets: "PATH=${config.home.profileDirectory}/bin"
  #     # Let's ensure that and add our variable.
  #     "PATH=${config.home.profileDirectory}/bin:${pkgs.coreutils}/bin:${pkgs.dbus}/bin" # A more robust PATH
  #     "QT_QPA_PLATFORM=wayland"
  #     "XDG_SESSION_TYPE=wayland" # Also good to set explicitly
  #   ];
  # };

  # systemd.user.services.kdeconnect-indicator = {
  #   Service.Environment = lib.mkOverride 90 [
  #     "PATH=${config.home.profileDirectory}/bin:${pkgs.coreutils}/bin:${pkgs.dbus}/bin"
  #     "QT_QPA_PLATFORM=wayland"
  #     "XDG_SESSION_TYPE=wayland"
  #   ];
  # };


  # services.kdeconnect = {
  #   enable = true;
  #   package = pkgs.kdePackages.kdeconnect-kde;
  #   # indicator = true;
  # };

  programs.firefox.enable = true;

  home.stateVersion = "24.11";
}
