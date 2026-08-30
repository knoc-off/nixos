{
  ...
}:
{
  nixos =
    {
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

      environment.systemPackages = with pkgs; [
        wl-clipboard
        xdg-utils
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

      # The share-picker used to segfault loading the session's Kvantum style
      # plugin, because hyprnix built it against a different Qt patch release
      # than nixpkgs (6.10.2 vs 6.10.1) and the plugin ABI did not match. That
      # needed hyprqt6engine built against hyprnix's Qt to work around. Now
      # that the whole stack comes from one nixpkgs there is only one Qt, so
      # the override is gone -- if the picker ever crashes on a style plugin
      # again, suspect a reintroduced Qt split rather than restoring this.
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

      # can this be auto calculated
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

      # could be overridden by other users?
      xdg.configFile."hypr/hyprland.lua".source = ./hyprland.lua;
      xdg.configFile."hypr/nix-env.lua".source = nixEnvLua;
      xdg.configFile."hypr/plugins.lua".source = pluginsLua;

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
