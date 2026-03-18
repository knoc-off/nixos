{
  inputs,
  lib,
  pkgs,
  config,
  theme,
  color-lib,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
  noctaliaCmd = lib.getExe config.programs.noctalia-shell.package;
  noctalia = cmd: "${noctaliaCmd} ipc call ${cmd}";

  mainMod = "SUPER";
  workspaces = builtins.genList (i: i + 1) 9;
  displayScale = 1.171339564;

  inherit (color-lib) setOkhslLightness setOkhslSaturation adjustOkhslHue;

  wsColors = theme.dark.workspaceColors;
  numWsColors = builtins.length wsColors;

  mkWsPalette = wsHex: let
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
    };

  # Generate solid-color PNG files and colors.json palettes at build time
  workspaceWallpapers =
    pkgs.runCommand "workspace-wallpapers" {
      nativeBuildInputs = [pkgs.imagemagick];
    } ''
      mkdir -p $out
      ${lib.concatImapStringsSep "\n" (i: color: ''
          magick -size 256x256 xc:'#${color}' $out/ws-${toString i}.png
          echo '${mkWsPalette color}' > $out/ws-${toString i}.json
        '')
        wsColors}
    '';

  # Daemon script: listens for Hyprland workspace changes, sets wallpaper + colors per-monitor
  workspaceWallpaperDaemon = pkgs.writeShellScript "workspace-wallpaper-daemon" ''
    set -euo pipefail

    NOCTALIA="${noctaliaCmd}"
    WALLPAPER_DIR="${workspaceWallpapers}"
    COLORS_FILE="$HOME/.config/noctalia/colors.json"
    NUM_COLORS=${toString numWsColors}

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
      "$NOCTALIA" ipc call wallpaper set "$WALLPAPER_DIR/ws-''${idx}.png" "$monitor" &
    }

    # Update the color palette based on the focused monitor's workspace
    update_colors() {
      local ws_id=$1
      local idx
      idx=$(ws_index "$ws_id")
      cat "$WALLPAPER_DIR/ws-''${idx}.json" > "$COLORS_FILE"
      # Nudge noctalia to re-read the colors file
      "$NOCTALIA" ipc call colorScheme setGenerationMethod "tonal-spot" &
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
      if "$NOCTALIA" ipc call state all >/dev/null 2>&1; then
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
in {
  imports = [
    # ./plugins/hyprspace.nix        # needs upstream update for 0.54
    # ./plugins/xtra-dispatchers.nix  # hyprland-plugins lagging behind 0.54 API
    # ./plugins/hyprglass.nix # works, but not for layershell :(
    ./plugins/kinetic-scroll.nix
  ];

  # XWayland apps don't know the Wayland fractional scale, so they render at 96 DPI
  # and get compositor-upscaled (blurry). Setting Xft.dpi tells them the real DPI.
  xresources.properties."Xft.dpi" = builtins.floor (96 * displayScale);

  # Theme config for hyprqt6engine (used by hyprland-share-picker via XDPH service).
  # Matches Stylix font/icon settings so the screen-share picker looks consistent.
  xdg.configFile."hypr/hyprqt6engine.conf".text = let
    fonts = config.stylix.fonts;
  in ''
    theme {
        style = Fusion
        icon_theme = ${config.gtk.iconTheme.name}
        font = ${fonts.sansSerif.name}
        font_size = ${toString fonts.sizes.applications}
        font_fixed = ${fonts.monospace.name}
        font_fixed_size = ${toString fonts.sizes.terminal}
    }
  '';

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        # lock_cmd is triggered by `loginctl lock-session`
        lock_cmd = "${noctaliaCmd} ipc call lockScreen lock";
        # Always lock before sleep, regardless of idle state
        before_sleep_cmd = "loginctl lock-session";
        # Restore monitors after waking
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        {
          timeout = 300; # 5 minutes
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 600; # 10 minutes
          on-timeout = "hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on";
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
    package = inputs.hyprnix.packages.${system}.hyprland;
    systemd.enable = false; # UWSM handles session/systemd integration

    settings = {
      ecosystem.no_update_news = true;

      exec-once = [
        "${workspaceWallpaperDaemon}"
      ];

      monitor = [
        "eDP-1, preferred, 0x0, ${toString displayScale}"
        ", preferred, auto-center-up, 1"
      ];

      general.layout = "scrolling";

      misc = {
        disable_hyprland_logo = true;
        force_default_wallpaper = 0;
        focus_on_activate = true;
      };

      gestures.gesture = [
        "3, vertical, workspace"
        "3, left, dispatcher, layoutmsg, move +col"
        "3, right, dispatcher, layoutmsg, move -col"
      ];

      decoration = {
        rounding = 6;
      };

      animations = {
        enabled = true;
        bezier = [
          "snap, 0.2, 1, 0.3, 1"
        ];
        animation = [
          "global, 1, 2, snap"
          "workspaces, 1, 2, snap, slidevert"
        ];
      };

      input = {
        follow_mouse = 1;

        repeat_rate = 25;
        repeat_delay = 200;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
          middle_button_emulation = true;

          # maybe
          # disable_while_typing = true;

          scroll_factor = 0.25;
        };
      };

      workspace = [
        "w[tv1], gapsout:0, gapsin:0"
        "f[1], gapsout:0, gapsin:0"
      ];

      windowrule = [
        # No borders/rounding when single tiled window or fullscreen
        "match:float 0, match:workspace w[tv1], border_size 0, rounding 0"
        "match:float 0, match:workspace f[1], border_size 0, rounding 0"

        "match:class org.gnome.Calculator, float on"
        "match:class org.gnome.Settings, float on"
        "match:class pavucontrol, float on"
        "match:class nm-connection-editor, float on"
        "match:class blueberry.py, float on"
        "match:class xdg-desktop-portal, float on"
        "match:class xdg-desktop-portal-gnome, float on"
        "match:class xdg-desktop-portal-hyprland, float on"
        "match:class org.gnome.Nautilus, float on"
        # "match:float 1, match:title (.*Open.*|.*Upload.*|.*Save.*|.*Select.*|.*Choose.*), size 45% 45%"
        # i think that the regex slows down on large titles?

        # Term has transparent background when resizing.
        "match:class com.mitchellh.ghostty, opaque on"
        "match:class com.mitchellh.ghostty, opacity 1.0 override 1.0 override"
        "match:class com.mitchellh.ghostty, no_blur on"

        # FreeCad:
        "match:initial_class ^org\\.freecad\\.FreeCAD$, match:initial_title ^Customize$, float on, center on, size (monitor_w*0.75) (monitor_h*0.75), no_max_size on"
        "match:class org\\.freecad\\.FreeCAD, match:title Expression editor, stay_focused on"
        # Freecad fixes transparency issue: https://github.com/hyprwm/Hyprland/discussions/13060
        "match:class org\\.freecad\\.FreeCAD, force_rgbx on"
        "match:class org\\.freecad\\.FreeCAD, opaque on"
        "match:class org\\.freecad\\.FreeCAD, opacity 1.0 override 1.0 override"
        "match:class org\\.freecad\\.FreeCAD, no_blur on"
        # "match:class org\\.freecad\\.FreeCAD, match:title Preferences, stay_focused on"

        # dragon-drop: sticky bottom-right drag-and-drop widget
        "match:class dragon-drop, float on"
        "match:class dragon-drop, pin on"
        "match:class dragon-drop, no_initial_focus on"
        "match:class dragon-drop, move (monitor_w-window_w-20) (monitor_h-window_h-20)"
      ];

      bind =
        [
          "${mainMod}, W, killactive"
          "${mainMod} SHIFT, L, exec, ${noctalia "lockScreen lock"}"

          "${mainMod}, left, layoutmsg, focus l"
          "${mainMod}, right, layoutmsg, focus r"
          "${mainMod}, up, movefocus, u"
          "${mainMod}, down, movefocus, d"

          "${mainMod}, h, layoutmsg, move -col"
          "${mainMod}, l, layoutmsg, move +col"
          "${mainMod}, k, movefocus, u"
          "${mainMod}, j, movefocus, d"

          # Scrolling layout
          "${mainMod}, period, layoutmsg, move +col"
          "${mainMod}, comma, layoutmsg, move -col"
          "${mainMod} SHIFT, period, layoutmsg, swapcol r"
          "${mainMod} SHIFT, comma, layoutmsg, swapcol l"
          "${mainMod}, bracketright, layoutmsg, colresize +conf"
          "${mainMod}, bracketleft, layoutmsg, colresize -conf"
          "${mainMod}, f, layoutmsg, fit visible"
          "${mainMod} SHIFT, f, layoutmsg, fit all"
          # promote,
          # "${mainMod} "

          # Runtime layout switching
          "${mainMod} ALT, s, layoutmsg, setlayout, scrolling"
          "${mainMod} ALT, d, layoutmsg, setlayout, dwindle"
          "${mainMod} ALT, m, layoutmsg, setlayout, master"

          # Media
          ", XF86AudioNext, exec, ${lib.getExe pkgs.playerctl} next"
          ", XF86AudioPrev, exec, ${lib.getExe pkgs.playerctl} previous"
          ", XF86AudioPlay, exec, ${lib.getExe pkgs.playerctl} play-pause"
          ", XF86AudioPause, exec, ${lib.getExe pkgs.playerctl} play-pause"
        ]
        ++ (map (i: "${mainMod}, ${toString i}, focusworkspaceoncurrentmonitor, ${toString i}") workspaces)
        ++ (map (i: "${mainMod} SHIFT, ${toString i}, movetoworkspace, ${toString i}") workspaces);

      bindle = let
        wpctl = "${pkgs.wireplumber}/bin/wpctl";
        brightnessctl = lib.getExe pkgs.brightnessctl;
      in [
        ", XF86AudioRaiseVolume, exec, ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0"
        ", XF86AudioLowerVolume, exec, ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86MonBrightnessUp, exec, ${brightnessctl} set +5%"
        ", XF86MonBrightnessDown, exec, ${brightnessctl} set 5%-"
      ];

      bindl = let
        wpctl = "${pkgs.wireplumber}/bin/wpctl";
      in [
        ", XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle"
      ];

      bindm = [
        "${mainMod}, mouse:272, movewindow"
        "${mainMod}, mouse:273, resizewindow"
      ];
    };
  };
}
