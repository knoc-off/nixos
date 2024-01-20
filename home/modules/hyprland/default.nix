{ inputs, pkgs, theme, config, ... }:
let
  # theres a few unchecked dependencies here.
  # like notify-send, etc. could link it like i do with fuzzle

  hyprland = inputs.hyprland.packages.${pkgs.system}.hyprland;
  plugins = inputs.hyprland-plugins.packages.${pkgs.system};


  wl-paste = "${pkgs.wl-clipboard}/bin/wl-paste";
  fuzzel = "${pkgs.fuzzel}/bin/fuzzel -b ${theme.base02}DD -t ${theme.base06}DD -m ${theme.base04}DD -C ${theme.base05}DD -s ${theme.base03}DD -S ${theme.base07}DD -M ${theme.base07}DD";
  notify-send = "${pkgs.libnotify}/bin/notify-send";

  launcher = pkgs.writeShellScriptBin "hypr" ''
    #!/${pkgs.bash}/bin/bash

    export WLR_NO_HARDWARE_CURSORS=1
    export _JAVA_AWT_WM_NONREPARENTING=1

    exec ${hyprland}/bin/Hyprland
  '';

  # Had to result to this, as the home-manager module for swaylock seems to be broken.
  swaylock-custom = pkgs.writeShellScriptBin "swaylock-custom" ''
    #!/${pkgs.bash}/bin/bash

    # Font
    font="DejaVu Sans Book"
    font_size="96"

    # Ring Size & Thickness
    indicator_radius="120"
    indicator_thickness="10"

    # Date & Time Format
    date_format="%Y.%m.%d"
    time_format="%H:%M:%S"

    # Background Effects
    effect_blur="$2" # 50x5
    effect_pixelate="$3" # 10
    #font = config.fontProfiles.regular.family;
    #indicator-caps-lock = true;


    exec ${config.programs.swaylock.package}/bin/swaylock \
    --layout-bg-color "${theme.base00}" \
    --layout-border-color "${theme.base02}" \
    --layout-text-color "${theme.base05}" \
    \
    --line-ver-color "${theme.green00}" \
    --inside-ver-color "${theme.green02}" \
    --ring-ver-color "${theme.green01}" \
    --text-ver-color "${theme.white00}" \
    \
    --line-wrong-color "${theme.red00}" \
    --inside-wrong-color "${theme.red02}" \
    --ring-wrong-color "${theme.red01}" \
    --text-wrong-color "${theme.white00}" \
    \
    --line-clear-color "${theme.base00}" \
    --inside-clear-color "${theme.base03}" \
    --ring-clear-color "${theme.yellow00}" \
    --text-clear-color "${theme.white00}" \
    \
    --ring-color "${theme.base02}" \
    --key-hl-color "${theme.base0B}" \
    --text-color "${theme.base05}" \
    \
    --line-color "${theme.base00}" \
    --inside-color "${theme.base01}" \
    --separator-color "${theme.base02}" \
    \
    --indicator-radius "$indicator_radius" \
    --indicator-thickness "$indicator_thickness" \
    \
    --clock \
    --datestr "$date_format" --timestr "$time_format" \
    \
    --screenshots \
    --effect-blur "$effect_blur" \
    --effect-pixelate "$effect_pixelate" \
    --grace $1 \
    --fade-in 0.5 \
    --daemonize

    #--effect-greyscale \

    # run as user to display notifications




    #--effect-custom /System/Config/Sway\ Lock\ Effects/Effects/twist-effect.c \
    #--font $font \
    #--font-size $font_size \
    #--effect-compose $effect_compose \
    #--image "/System/Appearance/Backgrounds/Lock/Eye.jpg" \
    #--effect-compose "50%x50%;center;/System/Appearance/Backgrounds/Lock/Eye.jpg" \
    #--screenshots \
    # --effect-vignette 0.5:0.25 \
    # --effect-custom ~/twist-effect.c \
    # --daemonize
    # DejaVuSansMono Mono
    # DejaVu Sans Book
    # /System/Appearance/Backgrounds/Lock/StarCraft.png
    # /System/Appearance/Backgrounds/Lock/Eye.jpg
    # $(cat /System/Config/Sway/Variables/Backgrounds/Lock)
  '';



  # hyprpaper config
  # need to put the wallpaper into the nix-store.
  wallpaper = pkgs.writeText "wallpaper"
    ''
      preload = ${./thinknix-d.png}
      wallpaper = eDP-1, ${./thinknix-d.png}
    '';# eDP-1 used to be preferred
in
{

  imports = [
    ./dunst.nix
  ];

  services.swayidle.enable = true;
  services.swayidle = {
    events = [
      { event = "before-sleep"; command = "${swaylock-custom}/bin/swaylock-custom 0 50x6 10"; }
      { event = "lock"; command = "lock"; }
    ];
    timeouts = [
      { timeout = 300; command = "${swaylock-custom}/bin/swaylock-custom 5 50x6 10"; }
      { timeout = 3600; command = "${pkgs.systemd}/bin/systemctl suspend"; }
    ];

  };

  programs.swaylock = {
    package = pkgs.swaylock-effects;
  };


  home.packages = [ swaylock-custom launcher pkgs.hyprpaper ];
  xdg.desktopEntries."org.gnome.Settings" = {
    name = "Settings";
    comment = "Gnome Control Center";
    icon = "org.gnome.Settings";
    exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome.gnome-control-center}/bin/gnome-control-center";
    categories = [ "X-Preferences" ];
    terminal = false;
  };

  wayland.windowManager.hyprland = {
    enable = true;
    package = hyprland;
    systemd.enable = true;
    xwayland.enable = true;
    # plugins = with plugins; [ hyprbars borderspp ];

    settings = {
      exec-once = [
        #"hyprctl setcursor Qogir 24"
        "hyprpaper --config ${wallpaper}"
      ];

      monitor = [
        #"eDP-1, highres, auto, 1.0"
        #"preferred, highres, auto, 1.0"
        ",highres, auto, 1"

        #  "HDMI-A-1, 2560x1440, 1920x0, 1"
      ];


      general = {
        gaps_in = 2;
        gaps_out = 4;
        border_size = 2;
        "col.active_border" = "0xff${theme.base02}";
        "col.inactive_border" = "0xff${theme.base01}";
        "col.nogroup_border_active" = "0xff${theme.base02}";
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
        disable_splash_rendering = true;
        force_default_wallpaper = 0;
        enable_swallow = false;
        # Any window started from kitty will be swallowed by the terminal
        swallow_regex = "kitty";
        # the exception should be anything containing the word 'NAN' or 'nvim'
        swallow_exception_regex = "NAN";
        background_color = "0xff${theme.base01}";
      };

      input = {

        kb_layout = "us";

        # focus follows mouse
        follow_mouse = 1;
        mouse_refocus = true;

        kb_options = "caps:super"; # caps as menu
        scroll_method = "2fg";

        # key repeat settings
        repeat_rate = 50;
        repeat_delay = 300;

        touchpad = {

          disable_while_typing = false;

          natural_scroll = true;
          scroll_factor = 0.5;
          middle_button_emulation = true;
          tap-and-drag = true;
          drag_lock = true;

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
        new_is_master = true;
        new_on_top = true;
        no_gaps_when_only = true;
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


      windowrule =
        let
          f = regex: "float, ${regex}";
        in
        [
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
          (f "Extension: (Bitwarden - Free Password Manager) - Bitwarden — Mozilla Firefox")
          (f "Steam - Browser")
          "workspace 7, title:Spotify"
        ];

      bind =
        let
          mainMod = "SUPER";

          binding = mod: cmd: key: arg: "${mod}, ${key}, ${cmd}, ${arg}";
          mvfocus = binding "${mainMod}" "movefocus";
          ws = binding "${mainMod}" "workspace";
          resizeactive = binding "${mainMod} CTRL" "resizeactive";
          mvactive = binding "${mainMod} ALT" "moveactive";
          mvtows = binding "${mainMod} SHIFT" "movetoworkspace";
          #e = "exec, ags -b hypr";
          arr = [ 1 2 3 4 5 6 7 8 9 ];
          yt = pkgs.writeShellScriptBin "yt" ''
            ${notify-send} "Opening video" "$(${wl-paste})"
            mpv "$(wl-paste)"
          '';
        in
        [
          #"CTRL SHIFT, R,  ${e} quit; ags -b hypr"
          #"SUPER, R,       ${e} -t applauncher"
          #", XF86PowerOff, ${e} -t powermenu"
          #"SUPER, Tab,     ${e} -t overview"
          #", XF86Launch4,  ${e} -r 'recorder.start()'"
          #",Print,         ${e} -r 'recorder.screenshot()'"
          #"SHIFT,Print,    ${e} -r 'recorder.screenshot(true)'"
          #"SUPER, Return, exec, xterm" # xterm is a symlink, not actually xterm
          #"SUPER, W, exec, firefox"
          #"SUPER, E, exec, wezterm -e lf"

          # youtube
          "${mainMod}, print,  exec, ${yt}/bin/yt"

          ## Master-Layout binds
          ", print, layoutmsg, swapwithmaster master"
          # IDK what key this is.
          ", XF86Fn, layoutmsg, addmaster"


          "${mainMod}, B, exec, ${notify-send} Battery \"$(cat /sys/class/power_supply/BAT0/status), $(cat /sys/class/power_supply/BAT0/capacity)\""


          "${mainMod}, Tab, focuscurrentorlast"
          "${mainMod}, Delete, exit"
          "${mainMod}, W, killactive"
          "${mainMod}, V, togglefloating"
          "${mainMod}, F, fullscreen"
          "${mainMod}, O, fakefullscreen"
          "${mainMod}, P, togglesplit"
          "${mainMod}, SPACE, exec, ${fuzzel}"

          # group
          "${mainMod}, G, togglegroup, 0"
          ", page_down, changegroupactive, f"
          ", page_up, changegroupactive, b"
          "${mainMod}, A, exec,  ${swaylock-custom}/bin/swaylock-custom 0 120x6 10"

          # (${notify-send} \"Battery level: $(cat /sys/class/power_supply/BAT0/capacity)%\")

          (mvfocus "up" "u")
          (mvfocus "down" "d")
          (mvfocus "left" "l")
          (mvfocus "right" "r")
          #(ws "left" "e-1")
          #(ws "right" "e+1")
          #(mvtows "left" "e-1")
          #(mvtows "right" "e+1")
          (resizeactive "k" "0 -20")
          (resizeactive "j" "0 20")
          (resizeactive "l" "20 0")
          (resizeactive "h" "-20 0")
          (mvactive "k" "0 -20")
          (mvactive "j" "0 20")
          (mvactive "l" "20 0")
          (mvactive "h" "-20 0")
        ]
        ++ (map (i: ws (toString i) (toString i)) arr)
        ++ (map (i: mvtows (toString i) (toString i)) arr);

      bindle =
        [
          # pkgs.light
          # pkgs.wpctl
          ",XF86MonBrightnessUp,  exec,  light -A 10"
          ",XF86MonBrightnessDown,exec,  light -U 10"
          ",XF86KbdBrightnessUp,  exec,  light -A 10"
          ",XF86KbdBrightnessDown,exec,  light -U 10"
          ",XF86AudioRaiseVolume, exec,  wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
          ",XF86AudioLowerVolume, exec,  wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
        ];

      bindl =
        [
          ",XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ",F1, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ];

      bindm = [
        "SUPER, mouse:273, resizewindow"
        "SUPER, mouse:272, movewindow"
      ];

      decoration = {

        rounding = 10;
        inactive_opacity = 0.95;
        drop_shadow = false;
        shadow_range = 2;
        "col.shadow" = "0xff${theme.base01}";


        shadow_render_power = 2;

        dim_inactive = false;

        blur = {
          enabled = true;
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
        ];
        animation = [
          "windows, 1, 3, default"
          "windowsIn, 1, 2, default"
          "windowsOut, 1, 1, instant"
          "border, 1, 10, default"
          "borderangle, 1, 8, default"
          "fade, 1, 10, default"
          "workspaces, 1, 3, default"

          #"windows, 1, 5, myBezier"
          #"windowsOut, 1, 7, default, popin 80%"
          #"border, 1, 10, default"
          #"fade, 1, 7, default"
          #"workspaces, 1, 6, default"
        ];
      };

      plugin = {
        hyprbars = {
          bar_color = "rgb(2a2a2a)";
          bar_height = 28;
          col_text = "rgba(ffffffdd)";
          bar_text_size = 11;
          bar_text_font = "Ubuntu Nerd Font";

          buttons = {
            button_size = 0;
            "col.maximize" = "rgba(ffffff11)";
            "col.close" = "rgba(ff111133)";
          };
        };
      };
    };
  };
}
