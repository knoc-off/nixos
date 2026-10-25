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
        inherit (pkgs.stdenv.hostPlatform) system;
        config = {
          allowUnfree = true;
        };
      };

      inherit (self.lib.keyLayers) presets;

      # Flattens { application.pdf = [...]; video.mp4 = [...]; } into
      # { "application/pdf" = [...]; "video/mp4" = [...]; } for xdg.mimeApps.
      toMimeApps = lib.concatMapAttrs (
        type: lib.mapAttrs' (sub: apps: lib.nameValuePair "${type}/${sub}" apps)
      );

      # Shared by standalone mpv and jellyfin-desktop's embedded one.
      mpvRefreshRate = pkgs.runCommand "mpv-refresh-rate" { scriptName = "refresh-rate.lua"; } ''
        mkdir -p $out/share/mpv/scripts
        substitute ${./mpv-refresh-rate.lua} $out/share/mpv/scripts/refresh-rate.lua \
          --replace-fail @hyprctl@ ${lib.getExe' upkgs.hyprland "hyprctl"}
      '';

      # The embedded libmpv never reads ~/.config/mpv (config=no) and sets
      # other_conf as properties after mpv_initialize, where "scripts" is
      # ignored. The patch turns other_conf "load-script=<path>" lines into
      # mpv load-script commands, and hands direct-play HDR items to a
      # separate system mpv: the embedded one draws into Qt's sRGB surface,
      # which cannot carry HDR10 to the compositor.
      jellyfinDesktop = pkgs.jellyfin-desktop.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./jellyfin-desktop.patch ];
        # The external player is whatever "mpv" the session resolves: the
        # home-manager one, so it gets mpv.conf and refresh-rate.lua.
      });

      # Merged into the app's own settings file on activation: the app rewrites
      # that file itself, so it cannot be a read-only store symlink.
      jellyfinDesktopSettings = {
        # The default "bundled" start page navigates qrc: -> http, and the
        # NativeShell user script is lost on that hop (Qt 6.11): jellyfin-web
        # then loads only its HTML5 player, the server transcodes HEVC/DTS to
        # H.264/AAC and flattens HDR to bt709 (washed out). Starting on the
        # server URL keeps the mpv player plugin.
        path.startupurl_desktop = "http://localhost:8096/web/";
        # vaapi zero-copy instead of the default auto-copy readback.
        video.hardwareDecoding = "enabled";
        # Same cheap-render settings as standalone mpv's "fast" profile: the
        # UHD 630 render engine otherwise sits at 100% upscaling to 2160p.
        other.other_conf = lib.concatStringsSep "\n" [
          "scale=bilinear"
          "cscale=bilinear"
          "dscale=bilinear"
          "dither-depth=no"
          "correct-downscaling=no"
          "linear-downscaling=no"
          "sigmoid-upscaling=no"
          "hdr-compute-peak=no"
          "load-script=${mpvRefreshRate}/share/mpv/scripts/refresh-rate.lua"
        ];
      };
    in
    {
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      # The bridge is D-Bus activated by xdg-desktop-portal, so its
      # share/dbus-1/services entry has to be on the session bus search path.
      services.dbus.packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.hypr-kdeconnect-portal ];

      # That activation file delegates via SystemdService=, so the user manager
      # has to be able to resolve the unit by name.
      systemd.packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.hypr-kdeconnect-portal ];

      # Portals are declared here rather than per-user because
      # NIX_XDG_DESKTOP_PORTAL_DIR names a single directory: xdg-desktop-portal
      # reads one dir and stops, so a home-manager portal set does not merge
      # with this one, it replaces it (and loses whichever half it did not
      # define). hyprland-tv sets portalPackage = null to keep home-manager out.
      #
      # common.default is left to the hyprland module; config is attrsOf attrsOf
      # str, so these merge per key.
      xdg.portal = {
        extraPortals = [ self.packages.${pkgs.stdenv.hostPlatform.system}.hypr-kdeconnect-portal ];
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
        extraSpecialArgs = { inherit self inputs upkgs; };

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

              self.homeModules.noctalia
              self.homeModules.hyprland-tv
              ./away.nix
              ./files.nix
              self.homeModules.stylix

              self.homeModules.git

              self.homeModules.starship

              self.homeModules.kanata
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
              enable = false;
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

            home.sessionVariables = {
              XDG_SESSION_TYPE = "wayland";
            };

            # Strip Noctalia down to OSD / popups / notifications: no bar, no
            # dock. v5's schema is unrelated to v4's -- `bar.monitors` as an
            # allow-list is gone, panels are floating-vs-attached per surface
            # under [shell.panel] rather than one global toggle, and section
            # names are singular ([lockscreen], [osd], [notification]).
            #
            # bar.default.enabled = false rather than omitting `bar`
            # entirely: an absent `bar` table means "not configured, use
            # defaults" (one bar named "default", enabled), verified by
            # reading config_service.cpp -- omitting the section is not a way
            # to disable the bar. An explicit entry with enabled = false is
            # the actual off switch, keyed by the same "default" name v5 uses
            # when nothing else names it.
            programs.noctalia.settings = {
              bar.default.enabled = false;
              lockscreen.monitors = [ ];
              shell.panel = {
                control_center_placement = "floating";
                control_center_position = "center";
                wallpaper_placement = "floating";
                wallpaper_position = "center";
                session_placement = "floating";
                session_position = "center";
                launcher_position = "center";
              };
              notification.position = "bottom_right";
              osd.position = "bottom_center";
            };

            programs.mpv = {
              enable = true;
              scripts = [
                pkgs.mpvScripts.mpris
                mpvRefreshRate
              ];
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
                # Tiled, Hyprland composited every 4K frame on top of mpv's own
                # rendering (directScanoutBlockedBy: windowed mode).
                fullscreen = true;

                # 24/25 fps content cannot map evenly onto a 4K60 output (25 ->
                # 60 is a 2/3 pulldown judder). Interpolation was tried and
                # removed: tscale=oversample ghosted high-contrast motion
                # (white ice on dark water) and the cadence still showed. The
                # fix for that is matching the refresh rate, not blending.
                vo = "gpu-next";
                hwdec = "auto-safe";
                "video-sync" = "display-resample";
                # Pass HDR through instead of tone-mapping: mpv tags its surface
                # with the source colorspace, and refresh-rate.lua switches the
                # output to 10-bit cm=hdr for PQ/HLG content. Only for HDR (see
                # the hdr profile): with the hint on for SDR, mpv tags the
                # surface BT.1886 and Hyprland 0.56 "converts" that to its sRGB
                # output with the BT.709 OETF and a 100-nit -> 80-nit range,
                # which lifts the whole image (measured 128 -> 154) and clips
                # above ~90%. Untagged, Hyprland passes it through bit-exact.
                "target-colorspace-hint" = "no";
                "target-colorspace-hint-mode" = "source";

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
                hdr = {
                  "profile-desc" = "HDR passthrough: tag the surface so Hyprland gets PQ/HLG";
                  "profile-cond" = ''get("video-params/gamma") == "pq" or get("video-params/gamma") == "hlg"'';
                  "profile-restore" = "copy";
                  "target-colorspace-hint" = "yes";
                };
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

              # The UHD 630 render engine sat at 87-100% (intel_gpu_top) with
              # the default lanczos 1080p->2160p upscale and per-frame HDR peak
              # detection. "fast" drops to bilinear and hdr-compute-peak=no.
              defaultProfiles = [ "fast" ];

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

              # Jellyfin client for this box's own screen: plays through mpv,
              # so local files direct-play (4K/HDR/lossless audio) with no
              # server-side transcode. Also in the noctalia launcher.
              jellyfinDesktop
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

            # KDE Connect advertises this box to phones even with the projector
            # off, so it gets torn down when nobody's watching and comes back on
            # the first input event. GUI apps stay out of tv-active.target --
            # see the note in the tv-away module for why.
            tv.away.units = [ "kdeconnect" ];

            # A unit rather than a hyprland exec-once so tv-remote has a stable
            # name to start it by. It is never stopped by the idle policy.
            systemd.user.services.spotify = {
              Unit = {
                Description = "Spotify";
                PartOf = [ "graphical-session.target" ];
                After = [ "graphical-session.target" ];
              };
              Service = {
                ExecStart = "${pkgs.spotify}/bin/spotify";
                Slice = "app-graphical.slice";
                # A clean exit means you closed the window on purpose -- leave
                # it closed. Only crashes get restarted.
                Restart = "on-failure";
                RestartSec = 5;
              };
              Install.WantedBy = [ "graphical-session.target" ];
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
                  "32-jellyfin" = {
                    name = "Jellyfin";
                    command = "${tvRemote} app jellyfin";
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

            # Profiles live under a generated id, so merge into each one that
            # exists. A running instance overwrites the file on exit, hence
            # the restart hint rather than a silent no-op.
            home.activation.jellyfinDesktopSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
              for conf in "${config.xdg.dataHome}"/jellyfin-desktop/profiles/*/jellyfin-desktop.conf; do
                [ -f "$conf" ] || continue
                tmp=$(mktemp)
                if ${lib.getExe pkgs.jq} --argjson s ${lib.escapeShellArg (builtins.toJSON jellyfinDesktopSettings)} \
                    '.sections *= $s' "$conf" >"$tmp"; then
                  if ! cmp -s "$tmp" "$conf"; then
                    run install -m644 "$tmp" "$conf"
                    ${pkgs.procps}/bin/pgrep -x .jellyfin-deskt >/dev/null \
                      && echo "jellyfin-desktop: settings updated, restart it to apply"
                  fi
                fi
                rm -f "$tmp"
              done
            '';

            # A kded-modules unit lived here. It loaded Plasma kded module names
            # into a session with no Plasma, was WantedBy a hyprland.target that
            # doesn't exist (so it never ran), and its "kded_kdd" entry -- commented
            # upstream as critical for screen mirroring -- is not a real KDE Connect
            # module. Removed rather than fixed: mirroring isn't wanted, and remote
            # input goes through the RemoteDesktop portal instead.

            programs.firefox = {
              enable = true;
              configPath = "${config.xdg.configHome}/mozilla/firefox";
              # ff2mpv-rust launches whatever `mpv` is on PATH, i.e. the hm one
              # above, so links get the same mpv.conf and refresh-rate.lua.
              nativeMessagingHosts = [ pkgs.ff2mpv-rust ];
              # Policies rather than profiles.<name>.extensions: AMO keeps them
              # updated and the existing profile stays unmanaged.
              policies.ExtensionSettings =
                lib.mapAttrs
                  (_: slug: {
                    installation_mode = "force_installed";
                    install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
                  })
                  {
                    "uBlock0@raymondhill.net" = "ublock-origin";
                    "sponsorBlocker@ajay.app" = "sponsorblock";
                    "ff2mpv@yossarian.net" = "ff2mpv";
                    "{762f9885-5a13-4abd-9c77-433dcd38b8fd}" = "return-youtube-dislikes";
                  };
            };

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
