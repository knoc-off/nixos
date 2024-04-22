{ inputs
, pkgs
, theme
, config
, ...
}:
let
  # theres a few unchecked dependencies here.
  # like notify-send, etc. could link it like i do with fuzzle
  hyprland = inputs.hyprland.packages.${pkgs.system}.hyprland;
  plugins = inputs.hyprland-plugins.packages.${pkgs.system};

  fuzzel = "${pkgs.fuzzel}/bin/fuzzel -b ${theme.base02}DD -t ${theme.base06}DD -m ${theme.base04}DD -C ${theme.base05}DD -s ${theme.base03}DD -S ${theme.base07}DD -M ${theme.base07}DD";

  notify-send = "${pkgs.libnotify}/bin/notify-send";

  # move this to own module TODO
  # Had to result to this, as the home-manager module for swaylock seems to be broken.
  swaylock-custom = pkgs.writeShellScriptBin "swaylock-custom" ''
    exec ${config.programs.swaylock.package}/bin/swaylock \
    --layout-bg-color "${theme.base00}" \
    --layout-border-color "${theme.base02}" \
    --layout-text-color "${theme.base05}" \
    \
    --line-ver-color "${theme.green00}" \
    --inside-ver-color "${theme.base03}" \
    --ring-ver-color "${theme.green01}" \
    --text-ver-color "${theme.white00}" \
    \
    --line-wrong-color "${theme.red00}" \
    --inside-wrong-color "${theme.base02}" \
    --ring-wrong-color "${theme.red01}" \
    --text-wrong-color "${theme.white00}" \
    \
    --line-clear-color "${theme.base00}" \
    --inside-clear-color "${theme.base02}" \
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
    --indicator-radius "100" \
    --indicator-thickness "1" \
    \
    --clock \
    --datestr "%Y.%m.%d" --timestr "%H:%M:%S" \
    \
    --screenshots \
    --grace $1 \
    --effect-blur "$2" \
    --effect-pixelate "$3" \
    --fade-in $4 \
    --font-size 24 \
    --daemonize
  '';

  # hyprpaper config
  # need to put the wallpaper into the nix-store.
  wallpaper =
    pkgs.writeText "wallpaper"
      ''
        preload = ${./wallpaper-nixos.png}
        wallpaper = eDP-1, ${./wallpaper-nixos.png}
      '';
in
{

  imports = [
    ./dunst.nix
    ./pyprland.nix
    #./mako.nix
    #./wired-notify.nix
    ./eww.nix

  ];

  # Pomo timer, should move to its own module
  home.file."uairtest" = {
    target = ".config/uair/uair.toml";
    source = pkgs.writers.writeTOML "uair.toml" {
      defaults = {
        format = "\r{percent}\n#{time}\n";
      };
      sessions = [
        {
          id = "work";
          name = "Work";
          duration = "25m";
          command = "notify-send 'Work Done!'";
        }
        {
          id = "rest";
          name = "Rest";
          duration = "5m";
          command = "notify-send 'Rest Done!'";
        }
      ];
    };
  };
  services.swayidle.enable = true;
  services.swayidle = {
    events = [
      {
        event = "before-sleep";
        command = "${swaylock-custom}/bin/swaylock-custom 0 50x6 10 0";
      }
      {
        event = "lock";
        command = "lock";
      }
    ];
    timeouts = [
      {
        timeout = 300;
        command = "${swaylock-custom}/bin/swaylock-custom 5 50x6 10 0.5";
      }
      {
        timeout = 600;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
  };


  programs.swaylock = {
    package = pkgs.swaylock-effects;
  };

  home.packages = [
    swaylock-custom
    pkgs.hyprpaper
  ];
  xdg.desktopEntries."org.gnome.Settings" = {
    name = "Settings";
    comment = "Gnome Control Center";
    icon = "org.gnome.Settings";
    exec = "env XDG_CURRENT_DESKTOP=gnome ${pkgs.gnome.gnome-control-center}/bin/gnome-control-center";
    categories = [ "X-Preferences" ];
    terminal = false;
  };



  # ~~~~~~~~~

  pyprland = {
    enable = true;
    extraPlugins = [
      "expose"
    ];
    settings = {
      scratchpads = {
        file = {
          animation = "fromBottom";
          command = "nautilus";
          class = "filemanager";
          size = "75% 60%";
          unfocus = "hide";
        };
        volume = {
          animation = "fromRight";
          command = "pavucontrol";
          class = "pavucontrol";
          lazy = true;
          size = "40% 90%";
          unfocus = "hide";
        };
        stb-logs = {
          animation = "fromTop";
          command = "kitty --class kitty-stb-logs stbLog";
          class = "kitty-stb-logs";
          lazy = true;
          size = "75% 40%";
        };
        term = {
          animation = "fromTop";
          command = "kitty --class kitty-dropterm";
          class = "kitty-dropterm";
          unfocus = "hide";
          size = "75% 60%";
        };
      };
    };
  };

  # ~~~~~~~~~


  wayland.windowManager.hyprland = {
    enable = true;
    package = hyprland;
    systemd.enable = true;
    xwayland.enable = true;
    plugins = with plugins; [ ];

    settings = {
      exec-once = [

        "hyprpaper --config ${wallpaper}"
        "pypr"
        "${pkgs.wayland-pipewire-idle-inhibit}/bin/wayland-pipewire-idle-inhibit"
        #"hyprctl dispatch movetoworkspacesilent 1,firefox"
        #"hyprctl dispatch movetoworkspacesilent 2,kitty"
      ];

      monitor = [
        #"eDP-1, highres, auto, 1.0"
        #"preferred, highres, auto, 1.0"
        #",highres, auto, 1"
        ",preferred,auto,1"

        #  "HDMI-A-1, 2560x1440, 1920x0, 1"
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
        #kb_options = "caps:super";
        kb_file = "${./output.xkb}";

        # focus follows mouse
        follow_mouse = 1;
        mouse_refocus = true;

        # Caps as super, and change repeat rate of the key 'a' to 5ms
        #    kb_layout = us
        #    kb_variant =
        #    kb_model =
        #    kb_options =
        #    kb_rules =
        #xkb_symbols "custom" {
        #  key <KEY> { [ repeat ] };
        #};

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
        new_is_master = false;
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

      windowrule =
        let
          f = regex: "float, ${regex}";
          w = regex: (number: "workspace ${builtins.toString number}, ${regex}");
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
          (f ".gscreenshot-wrapped")
          (w "Spotify" 7)
          #"fakefullscreen, org.kde.falkon"
          #"workspace 7, title:Spotify"
        ];

      windowrulev2 =
        let
          float = class: (title: "float, class:(${class}), title:(${title})");
          pin = class: (title: "pin, class:(${class}), title:(${title})");
          opacity = class: (title: (opacity: "opacity ${builtins.toString opacity}, class:(${class}), title:(${title})"));
          fakeFullscreen = class: "fakefullscreen, class:(${class})";
          #size = class: (title: (size: "float, class:(${class}), title:(${title})"));
          idleinhibit = mode: (class: (title: "idleinhibit ${mode}, class:(${class}), title:(${title})"));
          window = class: (title: (to: "workspace ${to}, class:(${class}), title:(${title})"));
        in
        [
          #"idleinhibit always, class:(kitty), title:(.*)"
          #"idleinhibit focus, class:(firefox), title:(.*Youtube.*)"
          #(idleinhibit "focus" "firefox" ".*YouTube.*")
          (float "steam" ".*Browser.*")
          (float "steam" ".*Friends List.*")
          (window "thunderbird" ".*" "6")
          (fakeFullscreen "org.kde.falkon")
          #(window "firefox" ".*" "special:firefox")
        ];

      bind =
        let
          moveRelativeTo = pkgs.writeNuScript "mv"
          ''
            def main [-w, num: int] {
              let current_workspace = (hyprctl activeworkspace -j | from json | get id)
              mut requested_workspace = $current_workspace + $num
              if ($requested_workspace < 1 ) { $requested_workspace = 1 }
              if ($requested_workspace > 9 ) { $requested_workspace = 9 }
              if ($w) {
                hyprctl dispatch movetoworkspace $requested_workspace
              } else {
                hyprctl dispatch workspace $requested_workspace
              }
            }
          '';

          nu-focus = pkgs.writeNuScript
          "focus"
          ''
            def main [title: string] {
              let activeWindow = (hyprctl activewindow -j | from json)
              let tmp_var = $activeWindow.address

              let file_path = ("/tmp/focuswindow_" + $title)
              let file_exists = ( $file_path | path exists )

              if ($file_exists == false) {
                 let json_value = {state: 0, address: $tmp_var} | to json
                 $json_value | save -f $file_path
              }

              if (open $file_path | from json | get state) == 0 {
                 if $activeWindow.class == $title { return }
                 hyprctl dispatch focuswindow $title
                 (open $file_path | from json | update state 1 | to json | save -f $file_path)
                 (open $file_path | from json | update address $tmp_var | to json | save -f $file_path)
              } else {
                 let address = (open $file_path | from json | get address)
                 hyprctl dispatch focuswindow ("address:" + $address)
                 (open $file_path | from json | update state 0 | to json | save -f $file_path)
              }
            }
          '';

          screenshot-to-text = pkgs.writeNuScript "stt"
          ''
            def main [] {
              ${pkgs.gscreenshot}/bin/gscreenshot -s -f /tmp/gscreenshot-image.png
              ${pkgs.imagemagick}/bin/convert -colorspace gray -fill white  -resize 480%  -sharpen 0x1  /tmp/gscreenshot-image.png /tmp/gscreenshot-image-processed.jpg
              ${pkgs.tesseract}/bin/tesseract /tmp/gscreenshot-image-processed.jpg /tmp/tesseract-output
              cat /tmp/tesseract-output.txt | wl-copy
            }
          '';

          mainMod = "SUPER";
          binding = mod: cmd: key: arg: "${mod}, ${key}, ${cmd}, ${arg}";
          mvfocus = binding "${mainMod}" "movefocus";
          ws = binding "${mainMod}" "workspace";
          resizeactive = binding "${mainMod} CTRL" "resizeactive";
          mvactive = binding "${mainMod} ALT" "moveactive";
          mvtows = binding "${mainMod} SHIFT" "movetoworkspace";
          #e = "exec, ags -b hypr";
          arr = [ 1 2 3 4 5 6 7 8 9 ]; # could reduce this to just 1 .. 9 probably

          acpi = "${pkgs.acpi}/bin/acpi";




        in
        [
          ## Master-Layout binds
          "${mainMod}, Backslash, layoutmsg, swapwithmaster master"
          #", XF86Fn, layoutmsg, addmaster"

          "${mainMod}, B, exec, ${notify-send} Battery \"$(${acpi} -b | awk '{print $3, $4}')\""

          "${mainMod}, Tab, focuscurrentorlast"
          "${mainMod}, Delete, exit"
          "${mainMod}, W, killactive"
          "${mainMod}, V, togglefloating"
          "${mainMod}, equal, fullscreen"
          "${mainMod}, O, fakefullscreen"
          #"${mainMod}, P, togglesplit"
          "${mainMod}, SPACE, exec, ${fuzzel}"
          "${mainMod}, A, exec, ${nu-focus}/bin/focus firefox"

          # Scratch workspaces
          "${mainMod}, T, exec, pypr toggle term"
          "${mainMod}, F, exec, pypr toggle file"
          "${mainMod} SHIFT, SPACE, exec, pypr expose"

          # screenshot
          ", Print, exec, ${pkgs.gscreenshot}/bin/gscreenshot -sc"
          "SHIFT, Print, exec, ${screenshot-to-text}/bin/stt"

          # misc
          ", page_down, exec, ${moveRelativeTo}/bin/mv -1 -w" # Up arrow
          ", page_up, exec, ${moveRelativeTo}/bin/mv 1 -w"    # Down arrow
          ", Home, exec, ${moveRelativeTo}/bin/mv -1" # home sits where my left arrow is
          ", End, exec, ${moveRelativeTo}/bin/mv 1"   # end sits where my right arrow is


          # group
          "${mainMod}, G, togglegroup, 0"
          "${mainMod}, L, exec,  ${swaylock-custom}/bin/swaylock-custom 0 120x6 10 0"
          "${mainMod}, asciitilde, exec,  ${pkgs.kitty}/bin/kitty nx rt"

          # pomo timer
          #"${mainMod}, period, exec, ${pkgs.uair}/bin/uairctl toggle"
          #"${mainMod}, comma, exec, ${start-pomo}/bin/start-pomo work"
          #uair | yad --title "uair" --progress --no-buttons --css="* { font-size: 80px; }" & sleep 1 && uairctl resume
          #''${mainMod}, P, exec,  ''

          # special workspaces
          #"${mainMod} ALT, 1, movetoworkspace, special:firefox"
          #"${mainMod}, A, togglespecialworkspace, firefox"
          #"${mainMod} ALT, 2, movetoworkspace, special:2"
          #"${mainMod} ALT, 1, exec, echo \"20\" > /tmp/volume_control_fifo" # ${pkgs.volume-lerp}/bin/volume-lerp"
          "${mainMod} ALT, 2, togglespecialworkspace, 2"
          "${mainMod} ALT, 3, togglespecialworkspace, 3"
          "${mainMod} ALT, 4, togglespecialworkspace, 4"


          (mvfocus "up" "u")
          (mvfocus "down" "d")
          (mvfocus "left" "l")
          (mvfocus "right" "r")
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
        let
          light = "${pkgs.light}/bin/light";
          wpctl = "${pkgs.wireplumber}/bin/wpctl";
          inertia = "${pkgs.writeNuScript "inertia"
          ''
            def reset_values [target: path, time: float, value: float] {
                {
                    "value": ($value),
                    "time": ($time),
                } | to json | save -f $target
            }

            def main [
                name: string = "default",
                --increment (-i): float = 1.0,
                --initialValue (-I): float = 1.0,
                --speed (-s): float = 0.15
            ] {
                let datafile = ("/tmp/inertia-" + $name) | path expand
                if not (echo $datafile | path exists) {
                    reset_values $datafile 0 $initialValue
                }

                let old = (open $datafile) | from json

                let current_time = ${pkgs.ruby}/bin/ruby -e 'puts Time.now.to_f'
                let current_time = $current_time | into float
                let delta_time = (($old.time | into float) - ($current_time | into float)) | math abs

                if $delta_time > $speed {
                    reset_values $datafile $current_time $initialValue
                    return $initialValue
                }

                let new_value = ($old.value) + ($delta_time * $increment)
                echo $new_value
                reset_values $datafile $current_time $new_value
                return $new_value
            }
          ''}/bin/inertia";
          brightness = pkgs.writeNuScript "brightness" ''
            def main [-u] {
                let value = if ($u) {
                  ${inertia} brightnessUP --increment 1 --initialValue 0.5 --speed 0.15

                } else {
                  ${inertia} brightnessDOWN --increment 1 --initialValue 0.5 --speed 0.15
                }
                if ($u) {
                  ${pkgs.light}/bin/light -A ($value)
                } else {
                  ${pkgs.light}/bin/light -U ($value)
                }

                ${notify-bar} brightnessbar (${pkgs.light}/bin/light) (${pkgs.light}/bin/light)
                ${notify-msg} value $value
            }
          '';
          volumeScript = pkgs.writeNuScript "volume" ''
            def main [-u] {
              let value = if ($u) {
                ${inertia} volumeUP -i 1 -I 0.5 -s 0.15
              } else {
                ${inertia} volumeDOWN -i 1 -I 0.5 -s 0.15
              }

              let percentage = if ($u) {
                ($value | into string) + "%+"
              } else {
                ($value | into string) + "%-"
              }

              ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ $percentage

              #if ($value | into float) > 2 {
              #  ${pkgs.libcanberra-gtk3}/bin/canberra-gtk-play -i audio-volume-change -d "changeVolume"
              #}

              ${notify-bar} volbar (${pkgs.pamixer}/bin/pamixer --get-volume) (${pkgs.pamixer}/bin/pamixer --get-volume-human)
              ${notify-msg} value $value
            }
          '';
          notify-msg = "${pkgs.writeShellScriptBin "notify-msg" ''
            ${notify-send} -t 2000 -h string:x-canonical-private-synchronous:$1 -u low "''${@:2}"
          ''}/bin/notify-msg";
          notify-bar = "${pkgs.writeShellScriptBin "notify-bar" ''
            ${notify-send} -t 2000 -h string:x-canonical-private-synchronous:$1 -h int:value:$2 -u low "''${@:3}"
          ''}/bin/notify-bar";
        in
        [
          ",XF86MonBrightnessUp,  exec,  ${brightness}/bin/brightness -u"
          ",XF86MonBrightnessDown,exec,  ${brightness}/bin/brightness"
          ",XF86KbdBrightnessUp,  exec,  ${brightness}/bin/brightness -u"
          ",XF86KbdBrightnessDown,exec,  ${brightness}/bin/brightness"
          ",XF86AudioRaiseVolume, exec,  ${volumeScript}/bin/volume -u"
          ",XF86AudioLowerVolume, exec, ${volumeScript}/bin/volume"

        ];

      bindl =
        let
          wpctl = "${pkgs.wireplumber}/bin/wpctl";
        in
        [
          ",XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle"
          "SUPER, XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
        ];

      bindm = [
        "SUPER, mouse:273, resizewindow"
        "SUPER, mouse:272, movewindow"
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
          "workspaces, 1, 3, default"
        ];
      };
    };
  };
}
