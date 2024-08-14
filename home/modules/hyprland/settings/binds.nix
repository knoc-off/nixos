{
  pkgs,
  lib,
  theme,
  config,
  ...
}: let
  mainMod = config.wayland.windowManager.hyprlandCustom.modkey;
in {
  wayland.windowManager.hyprland = let
    #fuzzel = "${pkgs.fuzzel}/bin/fuzzel -b ${theme.base02}DD -t ${theme.base06}DD -m ${theme.base04}DD -C ${theme.base05}DD -s ${theme.base03}DD -S ${theme.base07}DD -M ${theme.base07}DD";
    notify-send = "${pkgs.libnotify}/bin/notify-send";
    notify-msg = "${pkgs.writeShellScriptBin "notify-msg" ''
      ${notify-send} -t 2000 -h string:x-canonical-private-synchronous:$1 -u low "''${@:2}"
    ''}/bin/notify-msg";
    notify-bar = "${pkgs.writeShellScriptBin "notify-bar" ''
      ${notify-send} -t 2000 -h string:x-canonical-private-synchronous:$1 -h int:value:$2 -u low "''${@:3}"
    ''}/bin/notify-bar";
  in {
    settings = {
      bind = let
        moveRelativeTo =
          pkgs.writeNuScript "mv"
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

        nu-focus =
          pkgs.writeNuScript
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

        screenshot-to-text =
          pkgs.writeNuScript "stt"
          ''
            def main [] {
              ${pkgs.gscreenshot}/bin/gscreenshot -s -f /tmp/gscreenshot-image.png
              ${pkgs.imagemagick}/bin/convert -colorspace gray -fill white  -resize 480%  -sharpen 0x1  /tmp/gscreenshot-image.png /tmp/gscreenshot-image-processed.jpg
              ${pkgs.tesseract}/bin/tesseract /tmp/gscreenshot-image-processed.jpg /tmp/tesseract-output
              cat /tmp/tesseract-output.txt | wl-copy
            }
          '';

        binding = mod: cmd: key: arg: "${mod}, ${key}, ${cmd}, ${arg}";
        mvfocus = binding "${mainMod}" "movefocus";
        ws = binding "${mainMod}" "workspace";
        resizeactive = binding "${mainMod} CTRL" "resizeactive";
        mvactive = binding "${mainMod} ALT" "moveactive";
        mvtows = binding "${mainMod} SHIFT" "movetoworkspace";
        #e = "exec, ags -b hypr";
        arr = [1 2 3 4 5 6 7 8 9]; # could reduce this to just 1 .. 9 probably

        acpi = lib.getExe pkgs.acpi;
      in
        [
          ## Master-Layout binds
          "${mainMod}, Backslash, layoutmsg, swapwithmaster master"
          #", XF86Fn, layoutmsg, addmaster"

          "${mainMod}, B, exec, ${notify-send} \"$(${acpi} -b | awk '{print $3, $4}')\""

          "${mainMod}, Tab, focuscurrentorlast"
          "${mainMod}, Delete, exit"
          "${mainMod}, W, killactive"
          #"${mainMod}, V, togglefloating"
          "${mainMod}, equal, fullscreen"
          "${mainMod}, O, fakefullscreen"
          #"${mainMod}, P, togglesplit"
          #"${mainMod}, SPACE, exec, ${fuzzel}"
          "${mainMod}, A, exec, ${nu-focus}/bin/focus firefox"

          # "${mainMod}, ALT, submap, metameta"
          # bind=ALT,R,submap,resize

          # Scratch workspaces
          "${mainMod}, T, exec, pypr toggle term"
          "${mainMod}, F, exec, pypr toggle file"
          "${mainMod}, S, exec, pypr toggle foxy"
          "${mainMod}, Z, exec, pypr toggle volume"
          "${mainMod} SHIFT, SPACE, exec, pypr expose"

          # launcher
          "${mainMod}, SPACE, exec, ${pkgs.ulauncher}/bin/ulauncher"

          # screenshot
          ", Print, exec, ${pkgs.gscreenshot}/bin/gscreenshot -sc"
          "SHIFT, Print, exec, ${screenshot-to-text}/bin/stt"

          # misc
          ", page_down, exec, ${moveRelativeTo}/bin/mv -1 -w" # Up arrow
          ", page_up, exec, ${moveRelativeTo}/bin/mv 1 -w" # Down arrow
          ", Home, exec, ${moveRelativeTo}/bin/mv -1" # home sits where my left arrow is
          ", End, exec, ${moveRelativeTo}/bin/mv 1" # end sits where my right arrow is

          # group
          "${mainMod}, G, togglegroup, 0"
          "${mainMod}, L, exec, swaylock-custom 0 120x6 10 0"
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
          "${mainMod} ALT, 1, togglespecialworkspace, 1"
          "${mainMod} ALT, 2, togglespecialworkspace, 2"
          "${mainMod} ALT, 3, togglespecialworkspace, 3"

          "${mainMod} ALT SHIFT, 1, movetoworkspace, special:1"
          "${mainMod} ALT SHIFT, 2, movetoworkspace, special:2"
          "${mainMod} ALT SHIFT, 3, movetoworkspace, special:3"

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

      bindle = let
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

              #${notify-bar} brightnessbar (${pkgs.light}/bin/light) ((${pkgs.light}/bin/light) | into int | math round)
              #${notify-msg} value $value
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

            #${notify-bar} volbar (${pkgs.pamixer}/bin/pamixer --get-volume) (${pkgs.pamixer}/bin/pamixer --get-volume-human)
            #${notify-msg} value $value
          }
        '';
      in [
        ",XF86MonBrightnessUp,  exec,  ${brightness}/bin/brightness -u"
        ",XF86MonBrightnessDown,exec,  ${brightness}/bin/brightness"
        ",XF86KbdBrightnessUp,  exec,  ${brightness}/bin/brightness -u"
        ",XF86KbdBrightnessDown,exec,  ${brightness}/bin/brightness"
        ",XF86AudioRaiseVolume, exec,  ${volumeScript}/bin/volume -u"
        ",XF86AudioLowerVolume, exec, ${volumeScript}/bin/volume"
      ];

      bindl = let
        wpctl = "${pkgs.wireplumber}/bin/wpctl";
        mute = "${pkgs.writeNuScript "mute" ''
          ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle
          ${notify-bar} volbar (${pkgs.pamixer}/bin/pamixer --get-volume) (${pkgs.pamixer}/bin/pamixer --get-volume-human)
        ''}/bin/mute";
      in [
        ",XF86AudioMute, exec, ${mute}"
        "SUPER, XF86AudioMute, exec, ${mute}"
      ];

      bindm = [
        "SUPER, mouse:273, resizewindow"
        "SUPER, mouse:272, movewindow"
      ];
    };
  };
}
