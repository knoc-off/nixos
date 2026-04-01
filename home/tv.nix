{
  lib,
  inputs,
  pkgs,
  upkgs,
  self,
  ...
} @ args: let
  noctalia' = cmd:
    lib.concatStringsSep " " (
      ["noctalia-shell" "ipc" "call"] ++ (lib.splitString " " cmd)
    );

  mkKeyLayers = import ./key-layers.nix {inherit lib;};

  navKeys = {
    h = {key = "left";};
    j = {key = "down";};
    k = {key = "up";};
    l = {key = "right";};
    d = {raw = "(multi (release-key rmet) (mwheel-accel-down 50 150 1.05 0.80))";};
    u = {raw = "(multi (release-key rmet) (mwheel-accel-up 50 150 1.05 0.80))";};
  };

  # maybe add things to spawn certain programs, etc?
  keyLayers = mkKeyLayers {
    base = {
      capsbinds = {
        ctrl = ["a" "b" "c" "f" "i" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
        keys = navKeys;
      };
    };
    browser = {
      classes = ["firefox" "chromium-browser"];
      capsbinds = {
        ctrl = ["enter" "tab" "a" "b" "c" "f" "i" "n" "o" "p" "q" "r" "s" "t" "v" "w" "x" "y" "z"];
        keys =
          navKeys
          // {
            g = {raw = "(tap-dance 200 ((multi (release-key rmet) C-end) (multi (release-key rmet) C-home)))";};
          };
      };
    };
  };
in {
  imports = [
    ./programs/terminal
    ./programs/terminal/ghostty
    ./tv-xdg-env.nix
    ./programs/terminal/programs/opencode.nix

    self.homeModules.noctalia
    self.homeModules.hyprland
    self.homeModules.stylix

    self.homeModules.git

    self.homeModules.starship

    self.homeModules.kanata
    self.homeModules.hyprkan
    {
      programs.hyprkan = {
        package = self.packages.${pkgs.stdenv.hostPlatform.system}.hyprkan;
        enable = true;
        service.enable = true;

        service.extraArgs = [
          "--port"
          "52545"
        ];

        rules = keyLayers.hyprkanRules;
      };
    }

    {
      services.kanata = {
        enable = true;
        package = upkgs.kanata-with-cmd;

        keyboards.main = {
          devices = []; # Auto-detect keyboards
          excludeDevices = [
            "Logitech USB Receiver"
          ];
          port = 52545;
          extraDefCfg = "danger-enable-cmd yes process-unmapped-keys yes";

          config = keyLayers.kanataConfig ''
            launcher (cmd ${noctalia' "launcher toggle"})
            dbl (tap-dance-eager 250 (XX @launcher))
          '';
        };
      };
    }
  ];

  #  gtk = {
  #    enable = true;
  #    theme = {
  #      name = "Breeze-Dark";
  #      package = pkgs.kdePackages.breeze-gtk;
  #    };
  #    iconTheme = {
  #      name = "breeze-dark";
  #      package = pkgs.kdePackages.breeze-icons;
  #    };
  #    cursorTheme = {
  #      name = "breeze_cursors";
  #      package = pkgs.kdePackages.breeze;
  #      size = 24;
  #    };
  #    font = {
  #      name = "Noto Sans";
  #      size = 10;
  #    };
  #    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
  #    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  #  };

  #   qt = {
  #     enable = true;
  #     platformTheme.name = "kde";
  #     style = {
  #       name = "breeze";
  #       package = pkgs.kdePackages.breeze;
  #     };
  #   };

  home.sessionVariables = {
    XDG_SESSION_TYPE = "wayland";
  };

  programs.mpv = {
    enable = true;
    scripts = [pkgs.mpvScripts.mpris];
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
      "protocol.udp" = {
        # Corrected typo here
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

    defaultProfiles = ["gpu-hq"];

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
      "ctrl+l" = ''
        apply-profile "low-latency-stream"; show-text "Low Latency Stream Profile Applied"'';
    };
  };

  home.packages = with pkgs; [
    (inputs.nixgl.packages.x86_64-linux.nixGLIntel)

    kdePackages.dolphin
    kdePackages.ark
    kdePackages.okular
    kdePackages.gwenview
    kdePackages.plasma-workspace
    kdePackages.kservice
    (writeShellScriptBin "tv-wakeup" ''
      echo 'on 0' | ${libcec}/bin/cec-client -s -d 1
    '')
    (writeShellScriptBin "tv-shutdown" ''
      echo 'standby 0' | ${libcec}/bin/cec-client -s -d 1
    '')

    kdePackages.breeze
    kdePackages.breeze-gtk
    kdePackages.breeze-icons
    kdePackages.qqc2-breeze-style
    noto-fonts
    noto-fonts-color-emoji
  ];

  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  xdg.portal = {
    enable = true;
    config = {
      common = {
        default = ["hyprland"];
        "org.freedesktop.impl.portal.ScreenCast" = ["kde"];
        "org.freedesktop.impl.portal.RemoteDesktop" = ["kde"];
      };
    };
    extraPortals = [
      pkgs.kdePackages.xdg-desktop-portal-kde
    ];
  };

  services.mako.enable = true;

  xdg.configFile."menus/applications.menu".source = "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

  xdg.dataFile."desktop-directories".source = "${pkgs.kdePackages.plasma-workspace}/share/desktop-directories";
  home.activation.rebuildKdeCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    export PATH="${pkgs.kdePackages.kservice}/bin:$PATH"
    kbuildsycoca6 --noincremental || echo "Warning: kbuildsycoca6 failed, but continuing..."
  '';

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
    kded-modules = {
      Unit = {
        Description = "KDED Modules";
        After = ["kded.service" "user-path-import.service"];
        PartOf = ["kded.service"];
      };
      Install.WantedBy = ["hyprland.target"];
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
