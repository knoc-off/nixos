{ lib, inputs, pkgs, self, hostname, user, config, ... }@args:

let
  generateService = serviceName: command: {
    Unit = {
      Description = "${serviceName} Service";
      PartOf = [ "hyprland.target" ];
      Requires = [ "hyprland.target" ];
      After = [ "user-path-import.service" ];
    };
    Install.WantedBy = [ "hyprland.target" ];
    Service = {
      Type = "simple";
      Restart = "on-failure";
      ExecStart = "/usr/bin/env ${command}";
      RestartSec = "1";
    };
  };

in {

  imports = [
    ./programs/terminal/kitty
    ./programs/terminal
    ./desktop/hyprland.nix ];

  # programs.kodi = {
  #   enable = true;
  #   #package = pkgs.kodi-wayland;
  #   # package = # pkgs.kodi.withPackages (exts: [ exts.pvr-iptvsimple ]);
  #   package = pkgs.kodi-wayland.withPackages (kodiPkgs:
  #     with kodiPkgs; [
  #       jellyfin
  #       youtube
  #       pvr-iptvsimple
  #       steam-controller
  #     ]);
  #   settings = { videolibrary.showemptytvshows = "true"; };
  #   sources = {
  #     video = {
  #       default = "movies";
  #       source = [
  #         # {
  #         #   name = "videos";
  #         #   path = "${config.home-manager.users.tv.xdg.userDirs.videos}/misc";
  #         #   allowsharing = "true";
  #         # }
  #         {
  #           name = "shows";
  #           path = "${config.xdg.dataHome}/shows";
  #           allowsharing = "true";
  #         }
  #         {
  #           name = "movies";
  #           path = "${config.xdg.dataHome}/movies";
  #           allowsharing = "true";
  #         }
  #       ];
  #     };
  #   };

  # };

  # systemd.user.services.steam = {
  #   Unit = {
  #     Description = "Steam Client";
  #     After = [ "graphical-session.target" ];
  #     PartOf = [ "graphical-session.target" ];
  #   };

  #   Service = {
  #     ExecStart =
  #       "${pkgs.steam}/bin/steam -silent"; # maybe i should just run "steam" and not pkgs.steam
  #     ExecStop = "${pkgs.procps}/bin/pkill -TERM steam";
  #     Restart = "on-failure";
  #     RestartSec = "5s";
  #     Environment =
  #       "LD_PRELOAD=${pkgs.pkgsi686Linux.extest}/lib/libextest.so"; # Only if using extest
  #     # Add other environment variables if needed
  #   };

  #   Install.WantedBy = [ "graphical-session.target" ];
  # };

  # services.dunst = { enable = true; };

  home.sessionVariables = {
    QT_QPA_PLATFORM = "wayland";
    # MOZ_ENABLE_WAYLAND = "1"; # For Firefox, if not already set elsewhere
    XDG_SESSION_TYPE = "wayland";
  };

  programs.mpv = {
    enable = true;
    scripts = [ pkgs.mpvScripts.mpris ];
    scriptOpts = {
      osc = {
        seekbarstyle = "bar";
        deadzonesize = 0.5;
        vidscale = false;
        visibility = "auto";
      };
    };

    config = {
      "save-position-on-quit" = true;
      "keep-open" = "always";
      "force-window" = true;
      "idle" = "yes";

      vo = "gpu";
      hwdec = "auto-safe";

      volume = 70;
      "audio-file-auto" = "fuzzy";

      # Temporarily comment these out or remove if they cause "option not found"
      # due to the module's rendering. Test if mpv works without them first.
      # "cache-default" = 81920;
      # "cache-backbuffer" = 20480;
      # If the above are problematic, you might need to set them via command line
      # or wait for a module fix. For testing UDP streaming, they might not be
      # strictly necessary if your local network is fast.

      "network-timeout" = 5;
      "ytdl-format" = "bestvideo[height<=?1080]+bestaudio/best";

      "osd-font-size" = 32;
      "sub-auto" = "fuzzy";
      "sub-font-size" = 48;

      "screenshot-format" = "png";
      "screenshot-directory" = "~/Pictures/mpv_screenshots";
    };

    profiles = {
      "low-latency-stream" = {
        "profile-desc" = "Profile for low-latency network streaming";
        "network-timeout" = 2;
        "cache" = "no";
        "demuxer-lavf-probescore" = 25;
        "vd-lavc-threads" = 1;
        "framedrop" = "vo";
      };
      "protocol.udp" = { # Corrected typo here
        "profile-desc" = "Settings for UDP streams";
        "profile" = "low-latency-stream"; # Inherit
        "demuxer-max-bytes" = "10M";
        "demuxer-readahead-secs" = 0.2;
      };
      "my-encoding-profile" = {
        "profile-desc" = "Profile for encoding output";
        vf = "format=yuv420p";
      };
    };

    defaultProfiles = [ "gpu-hq" ];

    bindings = {
      "WHEEL_UP" = "seek 5";
      "WHEEL_DOWN" = "seek -5";
      "SHIFT+UP" = "add volume 2";
      "SHIFT+DOWN" = "add volume -2";
      "q" = "quit-watch-later";
      "SPACE" = "cycle pause";
      "p" = "cycle pause";
      ">" = "playlist-next";
      "<" = "playlist-prev";
      "s" = "screenshot video";
      "S" = "screenshot window";
      # Corrected binding:
      "ctrl+l" = ''
        apply-profile "low-latency-stream"; show-text "Low Latency Stream Profile Applied"'';
    };
  };

  home.packages = with pkgs; [
    # The core KDE Connect application suite
    plasma5Packages.kdeconnect-kde
    (inputs.nixgl.packages.x86_64-linux.nixGLIntel)
  ];

  # 1. Enable KDE Connect Service
  # This starts the 'kdeconnectd' daemon for your user.
  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  # 2. Enable the KDE Daemon (kded)
  # This is the most critical step for screen mirroring.
  # It runs the background service that hosts the screen sharing module.
  # services.kded.enable = true;

  # 3. Configure XDG Portals for Wayland Integration
  # This ensures that applications use the KDE portal for screen sharing.
  xdg.portal = {
    enable = true;
    config = {
      common = {
        default = [ "hyprland" ]; # Use Hyprland portal by default
        # Explicitly route screen sharing to KDE portal for KDE Connect
        "org.freedesktop.impl.portal.ScreenCast" = [ "kde" ];
        "org.freedesktop.impl.portal.RemoteDesktop" = [ "kde" ];

        #"org.freedesktop.impl.portal.Screenshot" = "wlr";
      };
    };
    extraPortals = [
      pkgs.xdg-desktop-portal-kde # For KDE Connect screen sharing
      pkgs.xdg-desktop-portal-hyprland
    ];
  };

  # 5. Ensure a notification daemon is running
  # KDE Connect relies on this to show notifications from your phone.
  # Mako is a popular, lightweight choice for Wayland.
  services.mako.enable = true;
  # Alternatively, you could use another like swaync:
  # programs.swaync.enable = true;

  # nixpkgs = {
  #   config = {
  #     allowUnfree = true;
  #     allowUnfreePredicate = _pkg: true;
  #   };
  # };

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

  systemd.user.services = {
    #kdeconnect-indicator =
    #(generateService "kdeconnect-indicator" "kdeconnect-indicator");

    # Update your kded-modules service to include the KDE Connect Display module
    kded-modules = {
      Unit = {
        Description = "KDED Modules";
        After = [ "kded.service" "user-path-import.service" ];
        PartOf = [ "kded.service" ];
      };
      Install.WantedBy = [ "hyprland.target" ];
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.writeScript "start-kded-modules" ''
          #!/usr/bin/env zsh

          moduleNames=(
            "gtkconfig"
            "bluedevil"
            "networkmanagement"
            "networkstatus"
            "smbwatcher"
            "device_automounter"
            "kded_kdd"  # This is the KDE Connect Display module - CRITICAL for screen mirroring
          )

          for module in $moduleNames; do
            qdbus org.kde.kded6 /kded org.kde.kded6.loadModule $module
          done
        ''}";
        RemainAfterExit = true;
      };
    };
  };
  # systemd.user.services.kdeconnect-indicator = {
  #   Service.Environment = lib.mkOverride 90 [
  #     "PATH=${config.home.profileDirectory}/bin:${pkgs.coreutils}/bin:${pkgs.dbus}/bin"
  #     "QT_QPA_PLATFORM=wayland"
  #     "XDG_SESSION_TYPE=wayland"
  #   ];
  # };

  programs.firefox.enable = true;

  home.stateVersion = "24.11";
}
