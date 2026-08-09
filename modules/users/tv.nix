{ inputs, self }: {
  nixos =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      user = "tv";
      upkgs = import inputs.nixpkgs-unstable {
        inherit (pkgs) system;
        config = {
          allowUnfree = true;
        };
      };

      inherit (self.lib.keyLayers) presets;

      # maybe add things to spawn certain programs, etc?

      toMimeApps =
        attrs:
        builtins.foldl' (
          acc: topLevelName:
          let
            subSet = attrs.${topLevelName};
            mapped = builtins.mapAttrs (subKey: desktopFiles: {
              name = "${topLevelName}/${subKey}";
              value = desktopFiles;
            }) subSet;
          in
          builtins.foldl' (acc2: entry: acc2 // { ${entry.name} = entry.value; }) acc (
            builtins.attrValues mapped
          )
        ) { } (builtins.attrNames attrs);
    in
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      # The bridge is D-Bus activated by xdg-desktop-portal, so its
      # share/dbus-1/services entry has to be on the session bus search path.
      services.dbus.packages = [ self.packages.${pkgs.system}.hypr-kdeconnect-portal ];

      # That activation file delegates via SystemdService=, so the user manager
      # has to be able to resolve the unit by name.
      systemd.packages = [ self.packages.${pkgs.system}.hypr-kdeconnect-portal ];

      # Portals are declared here rather than per-user because
      # NIX_XDG_DESKTOP_PORTAL_DIR names a single directory: xdg-desktop-portal
      # reads one dir and stops, so a home-manager portal set does not merge
      # with this one, it replaces it (and loses whichever half it did not
      # define). hyprland-tv sets portalPackage = null to keep home-manager out.
      #
      # common.default is left to the hyprland module; config is attrsOf attrsOf
      # str, so these merge per key.
      xdg.portal = {
        extraPortals = [ self.packages.${pkgs.system}.hypr-kdeconnect-portal ];
        config.common = {
          # ScreenCast/Screenshot go to hyprland: xdp-kde implements these
          # against KWin, which doesn't exist in this session.
          "org.freedesktop.impl.portal.ScreenCast" = [ "hyprland" ];
          "org.freedesktop.impl.portal.Screenshot" = [ "hyprland" ];
          # The one interface xdph does not implement. Without this, KDE
          # Connect's mousepad plugin can't create a session at all, which
          # is why only the MPRIS-based features (volume, play/pause) work.
          "org.freedesktop.impl.portal.RemoteDesktop" = [ "hypr-kdeconnect" ];
        };
      };

      home-manager = {
        backupFileExtension = "bak";
        useGlobalPkgs = true;
        useUserPackages = true;
        extraSpecialArgs = { inherit self inputs; };

        users.${user} =
          {
            pkgs,
            lib,
            config,
            ...
          }:
          {
            imports = [
              self.homeModules.cli-tools
              self.homeModules.ghostty
              self.homeModules.opencode

              self.homeModules.noctalia
              self.homeModules.hyprland-tv
              self.homeModules.tv-away
              self.homeModules.tv-files
              self.homeModules.stylix

              self.homeModules.git

              self.homeModules.starship

              self.homeModules.kanata
              self.homeModules.hyprkan
              self.homeModules.keylayers
              {
                keyLayers = {
                  enable = true;
                  layers.base.capsbinds = {
                    ctrl = presets.baseCtrlKeys;
                    keys = presets.navKeys;
                  };
                  # tv uses native programs.firefox (not the custom firefox module
                  # that owns the browser layer), so declare it here.
                  layers.browser = {
                    classes = [
                      "firefox"
                      "chromium-browser"
                    ];
                    capsbinds = {
                      ctrl = presets.appCtrlKeys;
                      keys = presets.navKeys // {
                        g = presets.docNavG;
                      };
                    };
                  };
                };
              }
              {
                programs.hyprkan = {
                  package = self.packages.${pkgs.stdenv.hostPlatform.system}.hyprkan;
                  enable = true;
                  service.enable = true;

                  service.extraArgs = [
                    "--port"
                    "52545"
                  ];
                };
              }

              {
                services.kanata = {
                  enable = true;
                  package = upkgs.kanata-with-cmd;

                  keyboards.main = {
                    devices = [ ]; # Auto-detect keyboards
                    excludeDevices = [
                      "Logitech USB Receiver"
                    ];
                    port = 52545;
                    extraDefCfg = "danger-enable-cmd yes process-unmapped-keys yes";
                  };
                };
              }
            ];

            home = {
              username = user;
              homeDirectory = "/home/${user}";
            };

            # modules/stylix.nix only turns on the gtk/qt targets, shared with
            # every host. kde and mpv are TV-specific: Dolphin/Okular/Gwenview/Ark
            # are all KDE apps installed below, and qt alone only sets the
            # platform theme, not kdeglobals -- so without this they stayed
            # unthemed even with stylix enabled.
            stylix.targets = {
              kde.enable = true;
              mpv.enable = true;
            };

            # Couch-navigable file browser (F5 / tv-remote files). Media is
            # the btrfs subvolume from disks.btrfsLuks.extraSubvolumes in
            # systems/optiplex.nix; USB drives show up automatically under
            # /run/media/tv via services.gvfs + devmon.
            programs.tv-files = {
              enable = true;
              places = [
                {
                  name = "Media";
                  path = "/srv/media";
                  icon = "folder-videos";
                }
                {
                  name = "Home";
                  path = "/home/${user}";
                  icon = "user-home";
                }
                {
                  name = "Downloads";
                  path = "/home/${user}/Downloads";
                  icon = "folder-download";
                }
              ];
            };

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

            # Strip Noctalia down to OSD / popups / notifications: no bar, no dock.
            # bar.monitors is a whitelist where [] means "every screen", so a
            # sentinel name that matches nothing is what disables it. Panels stay
            # alive because general.allowPanelsOnScreenWithoutBar is already true;
            # noctalia then centers them on its own since there's no bar to attach
            # to. Lists concatenate on merge, hence mkForce on every one of them.
            programs.noctalia-shell.settings = {
              bar.monitors = lib.mkForce [ "__disabled__" ];
              bar.screenOverrides = lib.mkForce [ ];
              general.lockScreenMonitors = lib.mkForce [ ];
              ui.panelsAttachedToBar = lib.mkForce false;
              controlCenter.position = lib.mkForce "center";
              wallpaper.panelPosition = lib.mkForce "center";
              notifications.location = lib.mkForce "bottom_right";
              osd.location = lib.mkForce "bottom_center";
              appLauncher.position = "center";
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
                "ctrl+l" = ''apply-profile "low-latency-stream"; show-text "Low Latency Stream Profile Applied"'';
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

              qview # Image viewer (from tv-xdg-env.nix)
            ];

            services.kdeconnect = {
              enable = true;
              # No tray host in this session (noctalia's bar is disabled, and
              # only waybar/polybar populate tray.target), so the indicator
              # renders nowhere -- it is just another process holding the
              # kdeconnect bus name alive.
              indicator = false;
            };

            # kdeconnect ships a D-Bus activation file with no SystemdService=,
            # so dbus-daemon forks kdeconnectd as its own child, invisible to
            # systemd: stopping tv-active.target would leave that copy running
            # and talking to the phone. $XDG_DATA_HOME wins over the profile in
            # the session bus search path, so this shadows it and routes every
            # activation through the unit, making PartOf= authoritative.
            xdg.dataFile."dbus-1/services/org.kde.kdeconnect.service".text = ''
              [D-BUS Service]
              Name=org.kde.kdeconnect
              Exec=${config.services.kdeconnect.package}/bin/kdeconnectd
              SystemdService=kdeconnect.service
            '';

            # KDE Connect advertises this box to phones even with the projector off,
            # and Spotify keeps it in the Connect device list. Both get torn down
            # when nobody's watching and come back on the first input event.
            # Firefox is deliberately absent -- it stays up.
            tv.away = {
              units = [ "kdeconnect" ];
              apps.spotify = {
                description = "Spotify";
                command = "${pkgs.spotify}/bin/spotify";
                # Frozen rather than stopped so the TV stops showing up as a
                # Connect target on the phone without its window being torn
                # down mid-idle -- see the freeze option for why that matters.
                freeze = true;
              };
            };

            # Run-commands the phone can trigger. QJsonObject sorts by key, so
            # the numeric prefixes are what fix the button order on the phone.
            # kdeconnectd only re-sends this list on connect or on a
            # configChanged signal, hence the restart in the activation script.
            home.activation.kdeconnectCommands =
              let
                tvRemote = lib.getExe self.packages.${pkgs.stdenv.hostPlatform.system}.tv-remote;
                commands = {
                  "10-ws1" = {
                    name = "Workspace 1";
                    command = "${tvRemote} ws 1";
                  };
                  "11-ws2" = {
                    name = "Workspace 2";
                    command = "${tvRemote} ws 2";
                  };
                  "12-ws3" = {
                    name = "Workspace 3";
                    command = "${tvRemote} ws 3";
                  };
                  "13-ws4" = {
                    name = "Workspace 4";
                    command = "${tvRemote} ws 4";
                  };
                  "20-prev" = {
                    name = "Previous App";
                    command = "${tvRemote} prev";
                  };
                  "21-next" = {
                    name = "Next App";
                    command = "${tvRemote} next";
                  };
                  "30-firefox" = {
                    name = "Firefox";
                    command = "${tvRemote} app firefox";
                  };
                  "31-spotify" = {
                    name = "Spotify";
                    command = "${tvRemote} app spotify";
                  };
                  "40-close" = {
                    name = "Close Window";
                    command = "${tvRemote} close";
                  };
                  "50-launcher" = {
                    name = "Launcher";
                    command = "${tvRemote} launcher";
                  };
                  "55-files" = {
                    name = "Files";
                    command = "${tvRemote} files";
                  };
                  "60-sleep" = {
                    name = "Sleep Now";
                    command = "${tvRemote} sleep";
                  };
                };
                # The plugin stores its JSON inside a QSettings ini value, whose
                # quoting rules match a JSON string literal for this character
                # set -- so encoding twice produces the escaping it reads back.
                commandsFile = pkgs.writeText "kdeconnect-runcommand-config" ''
                  [General]
                  commands=${builtins.toJSON (builtins.toJSON commands)}
                '';
              in
              lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                for dev in "$HOME"/.config/kdeconnect/*/; do
                  case "$(basename "$dev")" in
                    config | trusted_devices | *.pem) continue ;;
                  esac
                  run install -Dm644 ${commandsFile} "$dev/kdeconnect_runcommand/config"
                done
                run systemctl --user try-restart kdeconnect.service || true
              '';

            # Notifications are served by noctalia; a second daemon would just fight
            # it for org.freedesktop.Notifications on the bus.

            xdg.configFile."menus/applications.menu".source =
              "${pkgs.kdePackages.plasma-workspace}/etc/xdg/menus/plasma-applications.menu";

            xdg.dataFile."desktop-directories".source =
              "${pkgs.kdePackages.plasma-workspace}/share/desktop-directories";
            home.activation.rebuildKdeCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              export PATH="${pkgs.kdePackages.kservice}/bin:$PATH"
              kbuildsycoca6 --noincremental || echo "Warning: kbuildsycoca6 failed, but continuing..."
            '';

            # A kded-modules unit lived here. It loaded Plasma kded module names
            # into a session with no Plasma, was WantedBy a hyprland.target that
            # doesn't exist (so it never ran), and its "kded_kdd" entry -- commented
            # upstream as critical for screen mirroring -- is not a real KDE Connect
            # module. Removed rather than fixed: mirroring isn't wanted, and remote
            # input goes through the RemoteDesktop portal instead.

            programs.firefox.enable = true;
            programs.firefox.configPath = "${config.xdg.configHome}/mozilla/firefox";

            # Inlined from tv-xdg-env.nix
            xdg = {
              mimeApps = {
                enable = true;
                defaultApplications = toMimeApps {
                  video = {
                    mp4 = [ "mpv.desktop" ];
                    x-matroska = [ "mpv.desktop" ];
                    webm = [ "mpv.desktop" ];
                    x-msvideo = [ "mpv.desktop" ];
                    quicktime = [ "mpv.desktop" ];
                    mpeg = [ "mpv.desktop" ];
                  };

                  audio = {
                    mpeg = [ "mpv.desktop" ];
                    ogg = [ "mpv.desktop" ];
                    wav = [ "mpv.desktop" ];
                    flac = [ "mpv.desktop" ];
                    aac = [ "mpv.desktop" ];
                    x-ms-wma = [ "mpv.desktop" ];
                  };

                  image = {
                    jpeg = [ "qview.desktop" ];
                    png = [ "qview.desktop" ];
                    gif = [ "qview.desktop" ];
                    bmp = [ "qview.desktop" ];
                    "svg+xml" = [ "qview.desktop" ];
                    tiff = [ "qview.desktop" ];
                    webp = [ "qview.desktop" ];
                  };

                  inode = {
                    directory = [ "org.kde.dolphin.desktop" ];
                  };

                  application = {
                    zip = [ "org.kde.ark.desktop" ];
                    x-rar = [ "org.kde.ark.desktop" ];
                    x-7z-compressed = [ "org.kde.ark.desktop" ];
                    x-tar = [ "org.kde.ark.desktop" ];
                    gzip = [ "org.kde.ark.desktop" ];
                    pdf = [ "org.kde.okular.desktop" ];
                  };
                };
              };
            };

            home.stateVersion = "24.11";
          };
      };
    };
}
