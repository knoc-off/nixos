{
  ...
}:
{
  nixos =
    {
      lib,
      pkgs,
      upkgs,
      ...
    }:
    {
      programs.hyprland = {
        enable = true;
        # Plugins are ABI-locked to the exact hyprland they load into, and the
        # third-party ones only compile against HEAD-ish releases, so the
        # compositor and portal come from upkgs alongside them.
        package = upkgs.hyprland;
        portalPackage = upkgs.xdg-desktop-portal-hyprland;
        withUWSM = true;
      };

      security.polkit.enable = true;

      # programs.uwsm puts uwsm's session units into /etc/systemd/user via
      # systemd.packages, so switch-to-configuration treats them as its own and
      # stops/starts them whenever the uwsm store path changes -- which happens
      # on any nixpkgs bump that rebuilds uwsm, since ExecStart= embeds the path.
      # Stopping wayland-session-bindpid@ fires its
      # OnSuccess=wayland-session-shutdown.target, i.e. a full session teardown,
      # which systemd then refuses ("Found ordering cycle ... Unable to break
      # cycle") while wayland-wm-env@'s ExecStopPost has already run cleanup-env
      # and wiped WAYLAND_DISPLAY/XDG_* from the user manager. Net result: a
      # half-torn-down session and activation exit code 4.
      systemd.user.services = lib.genAttrs [
        "wayland-session-bindpid@"
        "wayland-wm@"
        "wayland-wm-app-daemon"
        "wayland-session-waitenv"
      ] (_: {
        # These units come from the uwsm package, not from NixOS, so the
        # override has to be a drop-in rather than a replacement file.
        overrideStrategy = "asDropin";
        restartIfChanged = false;
        # A NixOS service drop-in defaults to injecting Environment=PATH/
        # LOCALE_ARCHIVE/TZDIR. Drop-ins are parsed after the main unit, so
        # those would win over uwsm's EnvironmentFile=%t/uwsm/env_session.conf
        # and hand the compositor a stub PATH. Only X-RestartIfChanged is wanted.
        environment = lib.mkForce { };
        path = lib.mkForce [ ];
      });

      environment.systemPackages = [
        pkgs.wl-clipboard
        pkgs.xdg-utils
        # Replaces the portal's built-in Qt share picker -- see the xdph.conf
        # comment on the home side. slurp is what the picker shells out to for
        # region selection, so it has to be on the session PATH.
        upkgs.hyprland-preview-share-picker
        pkgs.slurp
      ];

      xdg.portal = {
        enable = true;
        extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
        config.common.default = [
          "hyprland"
          "gtk"
        ];
      };

      environment.sessionVariables.NIXOS_OZONE_WL = "1";

      # The portal's bundled hyprland-share-picker is Qt, and it segfaults
      # whenever the session's Qt style plugin was built against a different
      # qtbase patch release than the portal: loading it recurses forever in
      # QProxyStyle::standardPalette until the stack blows. That is not a
      # hypothetical -- the portal comes from upkgs (qtbase 6.11.2) while
      # stylix's qt target pulls Kvantum/qt6ct from stable pkgs (6.11.1), and
      # QT_STYLE_OVERRIDE=kvantum makes the picker load the mismatched plugin.
      # The crash surfaces as "you must give permission" in the client, because
      # the portal reports the dead picker as a denial.
      #
      # Rather than keep the two Qt stacks in lockstep forever, the picker is
      # swapped for a GTK4 one (hyprland-preview-share-picker) which has no Qt
      # plugin path to get wrong. Wired up via xdph.conf on the home side.
    };

  home =
    {
      inputs,
      config,
      lib,
      pkgs,
      upkgs,
      self,
      ...
    }:
    let
      inherit (self.lib) color-lib theme;
      system = pkgs.stdenv.hostPlatform.system;
      noctaliaCmd = lib.getExe config.programs.noctalia.package;
      noctalia = cmd: "${noctaliaCmd} msg ${cmd}";

      # TODO: derive from monitor physical size/resolution instead of hardcoding,
      # if a reliable source for panel DPI turns up (hyprctl doesn't expose it).
      displayScale = 1.171339564;

      mainMod = "SUPER";

      # Each plugin file is self-contained: it builds its package and owns its
      # Lua (load + settings + binds/gestures). We concatenate the fragments into
      # hypr/plugins.lua, which hyprland.lua requires.
      hyprPlugins = [
        (import ./plugins/kinetic-scroll.nix { inherit pkgs upkgs lib; })
        (import ./plugins/scroll-overview.nix {
          inherit
            pkgs
            upkgs
            lib
            mainMod
            ;
        })
      ];

      pluginsLua = pkgs.writeText "plugins.lua" (lib.concatMapStringsSep "\n" (p: p.lua) hyprPlugins);

      nixEnvLua = pkgs.writeText "nix-env.lua" ''
        local M = {}
        M.noctalia = "${noctaliaCmd}"
        M.wpctl = "${pkgs.wireplumber}/bin/wpctl"
        M.brightnessctl = "${lib.getExe pkgs.brightnessctl}"
        M.playerctl = "${lib.getExe pkgs.playerctl}"
        M.qs_overview_cmd = "echo 'no'"
        M.display_scale = ${toString displayScale}
        return M
      '';
    in
    {
      # XWayland renders at 96 DPI without this -- compositor upscales (blurry)
      xresources.properties."Xft.dpi" = builtins.floor (96 * displayScale);

      services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "${noctaliaCmd} msg session lock"; # triggered by loginctl lock-session
            before_sleep_cmd = "loginctl lock-session"; # always lock before sleep
            after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'"; # restore monitors after wake
          };

          listener = [
            {
              timeout = 300; # 5 minutes
              on-timeout = "loginctl lock-session";
            }
            {
              timeout = 600; # 10 minutes
              on-timeout = "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'";
              on-resume = "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'";
            }
            {
              timeout = 1800; # 30 minutes
              on-timeout = "${pkgs.systemd}/bin/systemctl suspend";
            }
          ];
        };
      };

      wayland.windowManager.hyprland = {
        enable = true;
        package = upkgs.hyprland;
        systemd.enable = false; # UWSM handles session/systemd integration

        configType = "lua";
      };

      xdg.configFile."hypr/hyprland.lua".source = ./hyprland.lua;
      xdg.configFile."hypr/nix-env.lua".source = nixEnvLua;
      xdg.configFile."hypr/plugins.lua".source = pluginsLua;

      # Point xdg-desktop-portal-hyprland at the GTK4 picker instead of its
      # bundled Qt one, which crashes on the Qt patch-version split between the
      # upkgs portal and stylix's stable Qt stack (see the NixOS side).
      # Absolute store path, not a bare binary name: the portal unit ships an
      # empty Environment= and would otherwise depend on the user manager's
      # inherited PATH.
      xdg.configFile."hypr/xdph.conf".text = ''
        screencopy {
          custom_picker_binary = ${lib.getExe upkgs.hyprland-preview-share-picker}
        }
      '';

      home.activation.seedHyprUserConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        target="$HOME/.config/hypr/user.lua"
        if [ ! -f "$target" ]; then
          install -Dm644 ${./user-default.lua} "$target"
        fi
      '';

      systemd.user.services.workspace-wallpaper-daemon =
        let
          inherit (color-lib) setOkhslLightness setOkhslSaturation adjustOkhslHue;

          wsColors = theme.dark.workspaceColors;
          numWsColors = builtins.length wsColors;

          # v5's custom-palette loader only recognises this exact camelCase
          # "m"-prefixed key set, nested under a `dark` (and optionally
          # `light`) key -- see the base16Palette comment in modules/noctalia.nix
          # for how this was verified against the parser source. Only `dark`
          # is emitted here since this whole feature is dark-theme-only
          # (theme.dark.workspaceColors has no light counterpart).
          #
          # `terminal` is required, not optional -- see the comment on
          # mkPaletteMode in modules/noctalia.nix. Without it,
          # parseCommunityPaletteJson rejects the whole mode and every
          # workspace silently falls back to the builtin palette.
          mkWsPalette =
            wsHex:
            let
              base = "#${wsHex}";
              # Primary accent: bright, saturated version of the workspace hue
              primary = "#${setOkhslLightness 0.65 (setOkhslSaturation 0.85 base)}";
              secondary = "#${setOkhslLightness 0.60 (setOkhslSaturation 0.70 (adjustOkhslHue 0.08 base))}";
              tertiary = "#${setOkhslLightness 0.60 (setOkhslSaturation 0.70 (adjustOkhslHue (-0.12) base))}";
              error = "#${theme.dark.base08}";
              surface = "#${theme.dark.base00}";
              surfaceVar = "#${theme.dark.base01}";
              onSurface = "#${theme.dark.base05}";
              onSurfVar = "#${theme.dark.base04}";
              outline = "#${theme.dark.base03}";
              hover = "#${theme.dark.base02}";
              onBg = "#${theme.dark.base00}";
              onHover = "#${theme.dark.base06}";
            in
            builtins.toJSON {
              dark = {
                mPrimary = primary;
                mOnPrimary = onBg;
                mSecondary = secondary;
                mOnSecondary = onBg;
                mTertiary = tertiary;
                mOnTertiary = onBg;
                mError = error;
                mOnError = onBg;
                mSurface = surface;
                mOnSurface = onSurface;
                mSurfaceVariant = surfaceVar;
                mOnSurfaceVariant = onSurfVar;
                mOutline = outline;
                mShadow = "#000000";
                mHover = hover;
                mOnHover = onHover;
                terminal = {
                  normal = {
                    black = surface;
                    red = error;
                    green = "#${theme.dark.base0B}";
                    yellow = "#${theme.dark.base0A}";
                    blue = secondary;
                    magenta = tertiary;
                    cyan = primary;
                    white = onSurface;
                  };
                  bright = {
                    black = outline;
                    red = error;
                    green = "#${theme.dark.base0B}";
                    yellow = "#${theme.dark.base0A}";
                    blue = secondary;
                    magenta = tertiary;
                    cyan = primary;
                    white = "#${theme.dark.base07}";
                  };
                  foreground = onSurface;
                  background = surface;
                  cursor = "#${theme.dark.base09}";
                  cursorText = onBg;
                  selectionFg = onHover;
                  selectionBg = hover;
                };
              };
            };

          # Generate solid-color PNG files and named custom-palette JSONs at
          # build time. Palette files are copied into
          # ~/.config/noctalia/palettes/ver-<i>.json at daemon start (v5 only
          # discovers palettes that live there, per customPalettePath in
          # custom_palettes.cpp) and selected at runtime with `msg
          # color-scheme-set custom ws-<i>` -- v4's approach of overwriting one
          # mutable colors.json in place has no v5 equivalent; there is no
          # "just write the active palette" IPC call anymore, only "switch to
          # a palette that already exists on disk by name".
          workspaceWallpapers =
            pkgs.runCommand "workspace-wallpapers"
              {
                nativeBuildInputs = [ pkgs.imagemagick ];
              }
              ''
                mkdir -p $out
                ${lib.concatImapStringsSep "\n" (i: color: ''
                  magick -size 256x256 xc:'#${color}' $out/ws-${toString i}.png
                  echo '${mkWsPalette color}' > $out/ws-${toString i}.json
                '') wsColors}
              '';

          # Daemon script: listens for Hyprland workspace changes, sets wallpaper + colors per-monitor
          workspaceWallpaperDaemon = pkgs.writeShellScript "workspace-wallpaper-daemon" ''
            set -euo pipefail

            NOCTALIA="${noctaliaCmd}"
            WALLPAPER_DIR="${workspaceWallpapers}"
            PALETTE_DIR="$HOME/.config/noctalia/palettes"
            NUM_COLORS=${toString numWsColors}

            mkdir -p "$PALETTE_DIR"
            for f in "$WALLPAPER_DIR"/ws-*.json; do
              cp -f "$f" "$PALETTE_DIR/$(basename "$f")"
            done

            # Map workspace ID to index (1-indexed, wraps with modulo)
            ws_index() {
              local ws_id=$1
              echo $(( ((ws_id - 1) % NUM_COLORS) + 1 ))
            }

            # Set wallpaper for a specific monitor based on its active workspace
            update_monitor() {
              local monitor=$1
              local ws_id=$2
              local idx
              idx=$(ws_index "$ws_id")
              "$NOCTALIA" msg wallpaper-set "$monitor" "$WALLPAPER_DIR/ws-''${idx}.png" &
            }

            # Update the color palette based on the focused monitor's workspace
            update_colors() {
              local ws_id=$1
              local idx
              idx=$(ws_index "$ws_id")
              "$NOCTALIA" msg color-scheme-set custom "ws-''${idx}"
            }

            # Sync all monitors on startup
            sync_all() {
              local focused_ws=""
              ${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | "\(.name) \(.activeWorkspace.id) \(.focused)"' | while read -r mon ws focused; do
                update_monitor "$mon" "$ws"
                if [ "$focused" = "true" ]; then
                  update_colors "$ws"
                fi
              done
            }

            # Wait for noctalia to be ready
            for i in $(seq 1 30); do
              if "$NOCTALIA" msg status >/dev/null 2>&1; then
                break
              fi
              sleep 1
            done

            sync_all

            # Listen for Hyprland IPC events
            ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while IFS= read -r line; do
              case "$line" in
                workspacev2\>\>*)
                  # workspacev2>>ID,NAME - active workspace changed, update the focused monitor
                  ws_id="''${line#workspacev2>>}"
                  ws_id="''${ws_id%%,*}"
                  focused_mon=$(${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -r '.[] | select(.focused) | .name')
                  if [ -n "$focused_mon" ] && [ "$ws_id" -gt 0 ] 2>/dev/null; then
                    update_monitor "$focused_mon" "$ws_id"
                    update_colors "$ws_id"
                  fi
                  ;;
                focusedmon\>\>*)
                  # focusedmon>>MONNAME,WSID - focus moved to a different monitor
                  payload="''${line#focusedmon>>}"
                  mon="''${payload%%,*}"
                  ws_id="''${payload#*,}"
                  if [ -n "$mon" ] && [ "$ws_id" -gt 0 ] 2>/dev/null; then
                    update_monitor "$mon" "$ws_id"
                    update_colors "$ws_id"
                  fi
                  ;;
                moveworkspacev2\>\>*)
                  # moveworkspacev2>>WSID,WSNAME,MONNAME - workspace moved to different monitor
                  payload="''${line#moveworkspacev2>>}"
                  ws_id="''${payload%%,*}"
                  rest="''${payload#*,}"
                  mon="''${rest#*,}"
                  if [ -n "$mon" ] && [ "$ws_id" -gt 0 ] 2>/dev/null; then
                    update_monitor "$mon" "$ws_id"
                  fi
                  ;;
                monitoraddedv2\>\>*)
                  # New monitor connected - sync all
                  sleep 1
                  sync_all
                  ;;
              esac
            done
          '';
        in
        {
          Unit = {
            Description = "Hyprland workspace wallpaper and color daemon";
            After = [
              "noctalia.service"
              "graphical-session.target"
            ];

            PartOf = [ "graphical-session.target" ];
            ConditionEnvironment = "HYPRLAND_INSTANCE_SIGNATURE";
          };
          Service = {
            ExecStart = "${workspaceWallpaperDaemon}";
            Restart = "on-failure";
            RestartSec = 2;
          };
          Install.WantedBy = [ "graphical-session.target" ];
        };
    };
}
