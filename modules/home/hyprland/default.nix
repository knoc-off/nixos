{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  noctaliaCmd = lib.getExe config.programs.noctalia-shell.package;
  noctalia = cmd: "${noctaliaCmd} ipc call ${cmd}";

  mainMod = "SUPER";

  # Helper to generate workspace binds for 1-9
  workspaces = builtins.genList (i: i + 1) 9;
in {
  wayland.windowManager.hyprland = {
    enable = true;
    package = inputs.hyprnix.packages.${system}.hyprland;

    settings = {
      ecosystem.no_update_news = true;

      # Default layout: scrolling (new in 0.54, built-in)
      general.layout = "scrolling";

      # Per-workspace layout overrides:
      # workspace = [
      #   "1, layout:dwindle"
      #   "2, layout:master"
      #   "9, layout:monocle"
      # ];

      misc = {
        disable_hyprland_logo = true;
        force_default_wallpaper = 0;
        focus_on_activate = true;
        new_window_takes_over_fullscreen = 2;
      };

      input = {
        follow_mouse = 1;
        repeat_rate = 25;
        repeat_delay = 200;
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
          middle_button_emulation = true;
        };
      };

      gestures = {
        workspace_swipe_direction_lock = false;
      };

      dwindle = {
        pseudotile = true;
        preserve_split = true;
      };

      master = {
        orientation = "left";
        mfact = 0.65;
      };

      # -- Startup --
      exec-once = [
        (noctalia "startup")
      ];

      # -- Window rules --
      windowrulev2 = [
        "float, class:(org.gnome.Calculator)"
        "float, class:(org.gnome.Settings)"
        "float, class:(pavucontrol)"
        "float, class:(nm-connection-editor)"
        "float, class:(blueberry.py)"
        "float, class:(xdg-desktop-portal)"
        "float, class:(xdg-desktop-portal-gnome)"
        "float, class:(xdg-desktop-portal-hyprland)"
        "float, class:(org.gnome.Nautilus)"
        "float, title:(astal-popup-menu)"
        "size 45% 45%, floating:1, title:(.*Open.*|.*Upload.*|.*Save.*|.*Select.*|.*Choose.*)"
      ];

      # -- Keybinds --
      bind =
        [
          # Window management
          "${mainMod}, W, killactive"
          "${mainMod}, equal, fullscreen"
          "${mainMod}, Delete, exit"

          # Noctalia integration
          "${mainMod}, SPACE, exec, ${noctalia "launcher toggle"}"
          "${mainMod}, L, exec, ${noctalia "lockScreen lock"}"

          # Focus (arrow keys)
          "${mainMod}, up, movefocus, u"
          "${mainMod}, down, movefocus, d"
          "${mainMod}, left, movefocus, l"
          "${mainMod}, right, movefocus, r"

          # Move windows
          "${mainMod} SHIFT, up, movewindow, u"
          "${mainMod} SHIFT, down, movewindow, d"
          "${mainMod} SHIFT, left, movewindow, l"
          "${mainMod} SHIFT, right, movewindow, r"

          # Resize
          "${mainMod} CTRL, h, resizeactive, -20 0"
          "${mainMod} CTRL, l, resizeactive, 20 0"
          "${mainMod} CTRL, k, resizeactive, 0 -20"
          "${mainMod} CTRL, j, resizeactive, 0 20"

          # Scrolling layout messages
          "${mainMod}, period, layoutmsg, move +col"
          "${mainMod}, comma, layoutmsg, move -col"
          "${mainMod} SHIFT, period, layoutmsg, swapcol r"
          "${mainMod} SHIFT, comma, layoutmsg, swapcol l"
          "${mainMod}, bracketright, layoutmsg, colresize +conf"
          "${mainMod}, bracketleft, layoutmsg, colresize -conf"
          "${mainMod}, f, layoutmsg, fit visible"
          "${mainMod} SHIFT, f, layoutmsg, fit all"

          # Runtime layout switching (per-workspace)
          "${mainMod} ALT, s, layoutmsg, setlayout scrolling"
          "${mainMod} ALT, d, layoutmsg, setlayout dwindle"
          "${mainMod} ALT, m, layoutmsg, setlayout master"

          # Tab through group
          "${mainMod}, Tab, changegroupactive, f"

          # Screenshot
          ", Print, exec, ${lib.getExe pkgs.gscreenshot} -sc"

          # Clipboard: copy primary to clipboard
          "${mainMod}, C, exec, ${pkgs.wl-clipboard}/bin/wl-paste -p | ${pkgs.wl-clipboard}/bin/wl-copy"

          # Playerctl
          ", XF86AudioNext, exec, ${lib.getExe pkgs.playerctl} next"
          ", XF86AudioPrev, exec, ${lib.getExe pkgs.playerctl} previous"
          ", XF86AudioPlay, exec, ${lib.getExe pkgs.playerctl} play-pause"
          ", XF86AudioPause, exec, ${lib.getExe pkgs.playerctl} play-pause"
        ]
        # Workspace switch: SUPER + 1..9
        ++ (map (i: "${mainMod}, ${toString i}, workspace, ${toString i}") workspaces)
        # Move to workspace: SUPER + SHIFT + 1..9
        ++ (map (i: "${mainMod} SHIFT, ${toString i}, movetoworkspace, ${toString i}") workspaces);

      # Repeat-on-hold binds (volume / brightness)
      bindle = let
        wpctl = "${pkgs.wireplumber}/bin/wpctl";
        brightnessctl = lib.getExe pkgs.brightnessctl;
      in [
        ", XF86AudioRaiseVolume, exec, ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0"
        ", XF86AudioLowerVolume, exec, ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ", XF86MonBrightnessUp, exec, ${brightnessctl} set +5%"
        ", XF86MonBrightnessDown, exec, ${brightnessctl} set 5%-"
      ];

      # Locked binds (work on lockscreen)
      bindl = let
        wpctl = "${pkgs.wireplumber}/bin/wpctl";
      in [
        ", XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle"
      ];

      # Mouse binds
      bindm = [
        "${mainMod}, mouse:272, movewindow"
        "${mainMod}, mouse:273, resizewindow"
      ];
    };
  };
}
