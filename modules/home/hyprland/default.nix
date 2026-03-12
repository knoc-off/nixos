{
  inputs,
  lib,
  pkgs,
  config,
  ...
}: let
  system = pkgs.stdenv.hostPlatform.system;
  noctaliaCmd = lib.getExe config.programs.noctalia-shell.package;
  noctalia = cmd: "${noctaliaCmd} ipc call ${cmd}";

  mainMod = "SUPER";
  workspaces = builtins.genList (i: i + 1) 9;
in {
  imports = [
    # ./plugins/hyprspace.nix        # needs upstream update for 0.54
    # ./plugins/xtra-dispatchers.nix  # hyprland-plugins lagging behind 0.54 API
    # ./plugins/hyprglass.nix # works, but not for layershell :(
    ./plugins/kinetic-scroll.nix
  ];

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

      monitor = [
        "eDP-1, preferred, 0x0, 1.171339564"
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
        "match:float 1, match:title (.*Open.*|.*Upload.*|.*Save.*|.*Select.*|.*Choose.*), size 45% 45%"

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
