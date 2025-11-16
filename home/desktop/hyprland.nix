{
  config,
  color-lib,
  lib,
  theme,
  pkgs,
  inputs,
  ...
}: {
  imports = [./hyprland-binds.nix inputs.hyprland.homeManagerModules.default];

  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    font = "Droid Sans 9";
    location = "center";
    xoffset = 0;
    yoffset = 0;
    extraConfig = {
      modi = "drun,run";
      show-icons = true;
      display-drun = "Applications";
      display-run = "Run";
      drun-display-format = "{icon} {name}";
      clipboard-histroy = 20;
    };
    #theme = "~/path/to/your/rofi/theme.rasi";
  };

  # lockscreen
  programs.swaylock = {package = pkgs.swaylock-effects;};

  # wallpaper manager
  home.packages = [pkgs.hyprpaper];

  # Window manager
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = true;
    xwayland.enable = true;
    #plugins = with inputs.hyprland-plugins.packages.${pkgs.system}; [hyprexpo];
    # plugins = with pkgs.hyprlandPlugins; [hyprexpo];

    #package = inputs.hyprland.packages.${pkgs.system}.hyprland;

    settings = {
      ecosystem.no_update_news = true;
      exec-once = [
        "astal-notify"
        "${pkgs.wayland-pipewire-idle-inhibit}/bin/wayland-pipewire-idle-inhibit"
      ];

      # plugins, might move to new file.
      #plugin = {
      #  hyprexpo = {
      #    columns = 2;
      #    gap_size = 5;
      #    bg_col = "0xff${theme.dark.base00}";
      #    skip_empty = true;
      #    workspace_method = "first 1"; # [center/first] [workspace] e.g. first 1 or center m+1

      #    enable_gesture = true; # laptop touchpad
      #    gesture_fingers = 3; # 3 or 4
      #    gesture_distance = 300; # how far is the "max"
      #    gesture_positive = false; # positive = swipe down. Negative = swipe up.
      #  };
      #};

      monitor = [",preferred,auto-up,1"];

      general = {
        gaps_in = -1;
        gaps_out = -4;
        border_size = 4;
        "col.active_border" = "0xff${theme.dark.base0B}";
        "col.inactive_border" = "0xff${theme.dark.base0D}";
        "col.nogroup_border_active" = "0x00${theme.dark.base0D}"; # transparent
        "col.nogroup_border" = "0x99${theme.dark.base0D}";

        layout = "master";
        resize_on_border = true;

        hover_icon_on_border = true;

        snap = {
          enabled = true;
        };
      };

      group = {
        insert_after_current = true;
        focus_removed_window = true;
        "col.border_active" = "0xff${theme.dark.base0B}";
        "col.border_inactive" = "0x99${theme.dark.base0D}";
        "col.border_locked_active" = "0xff${theme.dark.base0F}";
        "col.border_locked_inactive" = "0x99${theme.dark.base0F}";

        groupbar = {
          font_size = 10;
          gradients = false;
          render_titles = false;
          scrolling = false;
          text_color = "0xff${theme.dark.base0D}";
          "col.active" = "0xff${theme.dark.base0A}";
          "col.inactive" = "0x99${theme.dark.base0A}";
          "col.locked_active" = "0xff${theme.dark.base0F}";
          "col.locked_inactive" = "0x99${theme.dark.base0F}";
        };
      };

      misc = {
        layers_hog_keyboard_focus = false;
        disable_hyprland_logo = true;
        disable_splash_rendering = true; # the setting does nothing...
        "col.splash" = "0x00000000";

        # new window will un-fullscreen current.
        new_window_takes_over_fullscreen = 2;
        force_default_wallpaper = 0;
        animate_manual_resizes = true;
        enable_swallow = false;
        # Any window started from kitty will be swallowed by the terminal
        swallow_regex = "kitty";
        #swallow_exception_regex = "NAN";
        background_color = "0x99${color-lib.setOkhslLightness 0.2 theme.dark.base00}";

        # variable refresh rate, 3 = only for fullscreen games, 0 off.
        vrr = 3;

        # allow windows to request focus.
        focus_on_activate = true;
      };

      cursor = {
        # warp_on_toggle_special = true;

        # warps to the last remembered location
        persistent_warps = true;
      };

      input = {
        kb_layout = "us";
        #kb_options = "caps:super"; # replaced by kantana

        # focus follows mouse
        follow_mouse = 1;
        mouse_refocus = true;

        scroll_method = "2fg";

        # key repeat settings
        repeat_rate = 25;
        repeat_delay = 200;

        touchpad = {
          disable_while_typing = false;

          natural_scroll = true;
          scroll_factor = 0.2;
          middle_button_emulation = true;
          tap-and-drag = true;
          drag_lock = false;

          clickfinger_behavior = false;
          tap-to-click = true;
        };
        sensitivity = 0;
        float_switch_override_focus = 2;
      };

      binds = {allow_workspace_cycles = true;};

      dwindle = {
        pseudotile = true;
        preserve_split = true;
        #no_gaps_when_only = true;
      };
      master = {
        # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
        orientation = "left";
        #always_center_master = true;
        new_on_top = true;
        #new_is_master = false;
        #no_gaps_when_only = true;

        #new
        special_scale_factor = 0.5;
        mfact = 0.65;
      };

      gestures = {
        workspace_swipe = true;
        workspace_swipe_direction_lock = false;
        workspace_swipe_forever = false;
        # dont go to the next populated window. go to the next window
        workspace_swipe_distance = 300;
        workspace_swipe_fingers = 3;
        # this doesent skip empty workspaces
        #workspace_swipe_numbered = true;
      };

      windowrulev2 = let
        # Floats a window based on its class regex
        floatClass = regex: "float, class:(${regex})";

        floatTitle = titleRegex: "float, title:(${titleRegex})";

        # Assigns a window to a workspace based on its class regex
        workspaceClass = regex: (number: "workspace ${builtins.toString number}, class:(${regex})");

        # Applies a generic rule to a window based on its class regex
        ruleClass = rule: regex: "${rule}, class:(${regex})";

        # Floats a window based on its class AND title regex
        floatClassTitle = class: (title: "float, class:(${class}), title:(${title})");

        # --- Other potential helpers (can be uncommented and used if needed) ---
        fakeFullscreen = class: "fakefullscreen, class:(${class})";
        assignWorkspace = class: (title: (to: "workspace ${to}, class:(${class}), title:(${title})"));
        setSize = class: (title: (size: "size ${size}, class:(${class}), title:(${title})"));
        # idleInhibitRule = mode: class: (title: "idleinhibit ${mode}, class:(${class}), title:(${title})");
      in [
        (floatClass "org.gnome.Calculator")
        (floatClass "org.gnome.Nautilus")
        (floatClass "pavucontrol")
        (floatClass "nm-connection-editor")
        (floatClass "blueberry.py")
        (floatClass "org.gnome.Settings")
        (floatClass "org.gnome.design.Palette")
        # (floatClass "Color Picker")
        (floatClass "xdg-desktop-portal")
        (floatClass "xdg-desktop-portal-gnome")
        (floatClass "transmission-gtk")
        (floatTitle "astal-popup-menu")
        # Need to escape the leading dot for regex
        (floatClass "\\.gscreenshot-wrapped")
        (floatClass "astal-popup-menu")
        (workspaceClass "Spotify" 7)
        # Rules for 'kando'
        (ruleClass "noblur" "kando")
        (ruleClass "opaque" "kando")
        (ruleClass "size 100% 100%" "kando")
        (ruleClass "noborder" "kando")
        (ruleClass "noanim" "kando")
        (ruleClass "float" "kando")
        (ruleClass "pin" "kando")

        # --- Rules from original 'windowrulev2' block ---
        # (idleInhibitRule "always" "kitty" ".*") # Example using a potential helper
        # (idleInhibitRule "focus" "firefox" ".*Youtube.*") # Example using a potential helper
        (floatClassTitle "steam" ".*Browser.*")
        (floatClassTitle "steam" ".*Friends List.*")
        # (assignWorkspace "thunderbird" ".*" "6") # Example using a potential helper
        # (fakeFullscreen "org.kde.falkon") # Example using a potential helper

        # --- Hardcoded rules ---
        # "opacity 0.5 0.5, floating:1"
        # "size >40% >30%, floating:1" # Example minimum size
        "noborder, class:(ulauncher), title:(.*)"
        "stayfocused, class:^(FreeCAD)$, title:^(Formula editor)$"
        # any window that is floating, and contains specific words in the title, will have a size of 45%x45%
        "size 45% 45%, floating:1, title:(.*Open.*|.*Upload.*|.*Save.*|.*Select.*|.*Choose.*)"
        # "opacity 0.5 0.5, floating:1"
        # "stayfocused, class:^(pinentry-)" # fix pinentry losing focus
        # "workspace special:firefox, class:(firefox), title:(.*)"
      ];

      decoration = {
        rounding = 0; # 10;
        inactive_opacity = 1;
        # drop_shadow = false;
        # shadow_range = 0;
        # "col.shadow" = "0xff${oklchToHex (setLightness 0.2 primary)}";
        # shadow_render_power = 2;
        dim_inactive = false;
        dim_strength = 0.2;

        shadow = {
          enabled = true;
        };

        blur = {
          enabled = false;
          size = 8;
          passes = 3;
          new_optimizations = "on";
          noise = 1.0e-2;
          contrast = 0.9;
          brightness = 0.8;
        };
      };

      #  animations {
      #
      # enabled = true
      #
      # bezier= b0,0,1,0,1.05
      #
      # bezier= b1,0,1.1,0,1.05
      #
      # animation = windows,1,4,b1,slide
      #
      # animation = windowsIn,1,4,b0,popin 88%
      #
      # animation = windowsOut,1,4,b0,slide
      #
      # animation = workspaces,1,3,default,slide
      #
      # }

      animations = {
        enabled = true;

        bezier = [
          #"myBezier, 0.05, 0.9, 0.1, 1.05"
          "myBezier, 0.00, 1, 0, 9"
          "instant, 0, 9, 0, 9"
          "popBezier, 0.34, 1.16, 0.64, 1"
          "slowStart, 0.32, 0, 0.67, 0"
          "fastSlow, 0.15, 0.67, 0.05, 1"
          "slowFast,  0.15, 0, 0.05, 1"
        ];
        animation = [
          "windows, 1, 1, slowFast"
          "windowsIn, 1, 1, default"
          "windowsOut, 0, 1, instant"
          "fadeOut, 0"
          "border, 1, 10, default"
          "borderangle, 1, 8, default"
          "fade, 1, 1, default"
          "fadeDim, 1, 1, slowFast"
          "workspaces, 1, 3, default"
          "specialWorkspace, 1, 4, default, slidevert"
        ];
      };
    };
  };
}
