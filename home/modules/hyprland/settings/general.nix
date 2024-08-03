{
  config,
  theme,
  pkgs,
  ...
}: let
  wallpaper = let
    wallpaper-img = pkgs.fetchurl {
      url = "https://images.squarespace-cdn.com/content/v1/6554594506867677bdd68b03/a30ca789-db30-4413-8dc5-40726c893d7a/SCAV+new+intro+bg+02+copy.jpg";
      sha256 = "sha256-oGjPyBq56rweu7/Lo9SJudF/vg7uL1X/qpus9fFkEmw="; # Replace with the actual SHA-256 hash
    };
  in
    pkgs.writeText "wallpaper"
    ''
      preload = ${wallpaper-img}
      wallpaper = eDP-1, ${wallpaper-img}
      splash = false
    '';
in {
  exec-once = [
    "hyprpaper --config ${wallpaper}"
    "pypr"
    "${pkgs.wayland-pipewire-idle-inhibit}/bin/wayland-pipewire-idle-inhibit"
  ];

  monitor = [
    ",preferred,auto,1"
  ];

  general = {
    gaps_in = -1;
    gaps_out = -2;
    border_size = 2;
    "col.active_border" = "0xff${theme.green00}";
    "col.inactive_border" = "0xff${theme.gray01}";
    "col.nogroup_border_active" = "0x00${theme.base02}"; # transparent
    "col.nogroup_border" = "0x99${theme.base01}";

    layout = "master";
    resize_on_border = true;
  };

  group = {
    insert_after_current = true;
    focus_removed_window = true;
    "col.border_active" = "0xff${theme.green01}";
    "col.border_inactive" = "0x99${theme.base03}";
    "col.border_locked_active" = "0xff${theme.red00}";
    "col.border_locked_inactive" = "0x99${theme.red01}";

    groupbar = {
      font_size = 10;
      gradients = false;
      render_titles = true;
      scrolling = false;
      text_color = "0xff${theme.base06}";
      "col.active" = "0xff${theme.blue00}";
      "col.inactive" = "0x99${theme.blue03}";
      "col.locked_active" = "0xff${theme.red00}";
      "col.locked_inactive" = "0x99${theme.red04}";
    };
  };

  misc = {
    layers_hog_keyboard_focus = false;
    disable_hyprland_logo = true;
    disable_splash_rendering = true; # the setting does nothing...
    "col.splash" = "0x00000000";
    new_window_takes_over_fullscreen = 2; # new window will un-fullscreen current.
    force_default_wallpaper = 0;
    animate_manual_resizes = true;
    enable_swallow = false;
    # Any window started from kitty will be swallowed by the terminal
    swallow_regex = "kitty";
    # the exception should be anything containing the word 'NAN' or 'nvim'
    swallow_exception_regex = "NAN";
    background_color = "0xff${theme.base01}";
  };

  input = {
    kb_layout = "us";
    kb_options = "caps:super";
    #kb_file = "${./output.xkb}";

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
      scroll_factor = 0.5;
      middle_button_emulation = true;
      tap-and-drag = true;
      drag_lock = false;

      clickfinger_behavior = false;
      tap-to-click = true;
    };
    sensitivity = 0;
    float_switch_override_focus = 2;
  };

  binds = {
    allow_workspace_cycles = true;
  };

  dwindle = {
    pseudotile = true;
    preserve_split = true;
    no_gaps_when_only = true;
  };
  master = {
    # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
    orientation = "left";
    always_center_master = true;
    new_on_top = true;
    #new_is_master = false;
    no_gaps_when_only = true;

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

  windowrule = let
    f = regex: "float, ${regex}";
    w = regex: (number: "workspace ${builtins.toString number}, ${regex}");
  in [
    (f "org.gnome.Calculator")
    (f "org.gnome.Nautilus")
    (f "pavucontrol")
    (f "nm-connection-editor")
    (f "blueberry.py")
    (f "org.gnome.Settings")
    (f "org.gnome.design.Palette")
    (f "Color Picker")
    (f "xdg-desktop-portal")
    (f "xdg-desktop-portal-gnome")
    (f "transmission-gtk")
    (f "com.github.Aylur.ags")
    (f ".gscreenshot-wrapped")
    (w "Spotify" 7)
    #"fakefullscreen, org.kde.falkon"
    #"workspace 7, title:Spotify"
  ];

  windowrulev2 = let
    float = class: (title: "float, class:(${class}), title:(${title})");
    fakeFullscreen = class: "fakefullscreen, class:(${class})";
    #size = class: (title: (size: "float, class:(${class}), title:(${title})"));
    window = class: (title: (to: "workspace ${to}, class:(${class}), title:(${title})"));
  in [
    #"idleinhibit always, class:(kitty), title:(.*)"
    #"idleinhibit focus, class:(firefox), title:(.*Youtube.*)"
    #(idleinhibit "focus" "firefox" ".*YouTube.*")
    (float "steam" ".*Browser.*")
    (float "steam" ".*Friends List.*")
    (window "thunderbird" ".*" "6")
    (fakeFullscreen "org.kde.falkon")

    "noborder,class:(ulauncher),title:(.*)"
    "stayfocused, class:^(FreeCAD)$, title:^(Formula editor)$"

    # windowrulev2 = stayfocused, class:^(pinentry-) # fix pinentry losing focus

    #(window "firefox" ".*" "special:firefox")
  ];

  decoration = {
    rounding = 3; # 10;
    inactive_opacity = 1;
    drop_shadow = false;
    shadow_range = 0;
    "col.shadow" = "0xff${theme.base01}";
    shadow_render_power = 2;
    dim_inactive = true;
    dim_strength = 0.20;

    blur = {
      enabled = false;
      size = 8;
      passes = 3;
      new_optimizations = "on";
      noise = 0.01;
      contrast = 0.9;
      brightness = 0.8;
    };
  };

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
      "windowsOut, 0, 1, instant" # Disable
      "fadeOut, 0"
      "border, 1, 10, default"
      "borderangle, 1, 8, default"
      "fade, 1, 1, default"
      "fadeDim, 1, 1, slowFast"
      "workspaces, 1, 3, default"
    ];
  };
}
