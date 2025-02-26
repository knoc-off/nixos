{ pkgs, lib, self, config, ... }:
let

  #writeNuScript = self.packages.${pkgs.system}.writeNuScript;
  inherit (self.packages.${pkgs.system}) writeNuScript;

  mainMod = config.wayland.windowManager.hyprlandCustom.modkey;
in {
  wayland.windowManager.hyprland = let
    #fuzzel = "${pkgs.fuzzel}/bin/fuzzel -b ${theme.base02}DD -t ${theme.base06}DD -m ${theme.base04}DD -C ${theme.base05}DD -s ${theme.base03}DD -S ${theme.base07}DD -M ${theme.base07}DD";
    notify-send = "${pkgs.libnotify}/bin/notify-send";
    notify-msg = "${
        pkgs.writeShellScriptBin "notify-msg" ''
          ${notify-send} -t 2000 -h string:x-canonical-private-synchronous:$1 -u low "''${@:2}"
        ''
      }/bin/notify-msg";
    notify-bar = "${
        pkgs.writeShellScriptBin "notify-bar" ''
          ${notify-send} -t 2000 -h string:x-canonical-private-synchronous:$1 -h int:value:$2 -u low "''${@:3}"
        ''
      }/bin/notify-bar";
  in {
    settings = {
      bind = let
        mkHdrop = { command, # The command to run (required)
          background ? false, # Launch in background if not running
          class ? null, # Set the window class name
          floating ? true, # Spawn as a floating window
          gap ? null, # Gap from screen edge in pixels
          size ? null, # Window size as { width = int; height = int; }
          insensitive ? false, # Case-insensitive class name matching
          position ? null
          , # Window position: "top", "bottom", "left", or "right"
          verbose ? false, # Show detailed notifications
          version ? false # Print version information
          }:
          let
            boolToFlag = name: value: if value then "-${name}" else "";
            nullableArg = name: value:
              if value != null then "-${name} ${toString value}" else "";
            hdrop = pkgs.writeShellScriptBin "hdrop" (builtins.readFile
              (builtins.fetchurl {
                url =
                  "https://raw.githubusercontent.com/hyprwm/contrib/main/hdrop/hdrop";
                sha256 = "02d1pcgqn707z9b91yf22l477idn8pdd3dpls3yz3ivdj6idx18r";
              }));

            args = lib.concatStringsSep " " (lib.filter (x: x != "") [
              (boolToFlag "b" background)
              (nullableArg "c" class)
              (boolToFlag "f" floating)
              (nullableArg "g" gap)
              (if size != null then
                "-w ${toString size.width} -h ${toString size.height}"
              else
                "")
              (boolToFlag "i" insensitive)
              (nullableArg "p" position)
              (boolToFlag "v" verbose)
              (boolToFlag "V" version)
            ]);
          in "${hdrop}/bin/hdrop ${args} ${command}";

        moveRelativeTo = writeNuScript "mv" ''
          def main [-w, num: int] {
            let current_workspace = (hyprctl activeworkspace -j | from json | get id)
            mut requested_workspace = $current_workspace + $num
            if ($w) {
              hyprctl dispatch movetoworkspace $requested_workspace
            } else {
              hyprctl dispatch workspace $requested_workspace
            }
          }
        '';

        execute_lua_in_nvim = pkgs.writeShellScriptBin "execute_lua_in_nvim" ''
          # Function to execute Lua code in Neovim
          execute_lua_in_nvim() {
            local title="$1"
            local lua_code="$2"

            # Extract Neovim PID from window title (expects format '<title> - <PID>')
            if [[ "$title" =~ [[:space:]]-[[:space:]]([0-9]+)$ ]]; then
              local nvim_pid="''${BASH_REMATCH[1]}"
            else
              echo "No PID found in the title"
              return 1
            fi

            # Construct Neovim socket path
            local nvim_socket="/tmp/nvim_''${nvim_pid}.socket"

            # Check if Neovim socket exists
            if [[ ! -S "$nvim_socket" ]]; then
              echo "Neovim socket does not exist"
              return 1
            fi

            # Escape single quotes in the Lua code
            local escaped_lua_code
            escaped_lua_code=$(printf '%s' "$lua_code" | sed "s/'/'''/g")

            # Execute Lua code in Neovim and get the result
            local result
            result=$(nvim --headless --server "$nvim_socket" --remote-expr "ExecuteLua('$escaped_lua_code')")

            echo "$result"
          }
        '';

        # This script defines a function `screenshot-to-text` that captures a screenshot, processes the image,
        # extracts text from it using OCR, and copies the extracted text to the clipboard.
        #
        # The script performs the following steps:
        # 1. Captures a screenshot of a selected area and saves it as `/tmp/gscreenshot-image.png`.
        # 2. Converts the screenshot to grayscale, resizes it, and sharpens the image, saving the processed image as `/tmp/gscreenshot-image-processed.jpg`.
        # 3. Uses Tesseract OCR to extract text from the processed image and saves the text to `/tmp/tesseract-output.txt`.
        # 4. Copies the extracted text to the clipboard using `wl-copy`.
        screenshot-to-text = writeNuScript "stt" ''
          def main [] {
            ${pkgs.gscreenshot}/bin/gscreenshot -s -f /tmp/gscreenshot-image.png
            ${pkgs.imagemagick}/bin/convert -colorspace gray -fill white  -resize 480%  -sharpen 0x1  /tmp/gscreenshot-image.png /tmp/gscreenshot-image-processed.jpg
            ${pkgs.tesseract}/bin/tesseract /tmp/gscreenshot-image-processed.jpg /tmp/tesseract-output
            cat /tmp/tesseract-output.txt | wl-copy
          }
        '';

        fancyfocusscript = import ./window-move.nix { inherit pkgs self; };

        #{
        #    "address": "0x3e036f40",
        #    "mapped": true,
        #    "hidden": false,
        #    "at": [0, 9],
        #    "size": [1463, 1495],
        #    "workspace": {
        #        "id": 8,
        #        "name": "8"
        #    },
        #    "floating": false,
        #    "pseudo": false,
        #    "monitor": 0,
        #    "class": "kitty",
        #    "title": "nixos - 73648",
        #    "initialClass": "kitty",
        #    "initialTitle": "kitty",
        #    "pid": 7675,
        #    "xwayland": false,
        #    "pinned": false,
        #    "fullscreen": 0,
        #    "fullscreenClient": 0,
        #    "grouped": ["0x3e036f40", "0x3e068e60"],
        #    "tags": [],
        #    "swallowing": "0x0",
        #    "focusHistoryID": 0
        #}

        fancyGroupScript = writeNuScript "fancyGroup" ''
          def main [group: string] {
            let data = (hyprctl activewindow -j | from json)
            # get grouped data, if 0 then create group. else move out of group.
            let grouped = ($data.grouped | length)
            if ($grouped == 0) {
              hyprctl dispatch togglegroup
            } else {
              hyprctl dispatch moveoutofgroup
            }
          }
      '';

        binding = mod: cmd: key: arg: "${mod}, ${key}, ${cmd}, ${arg}";
        fancyfocus = key: dir:
          "${mainMod}, ${key}, exec, ${fancyfocusscript}/bin/fancyfocus ${dir}";
        ws = binding "${mainMod}" "workspace";
        resizeactive = binding "${mainMod} CTRL" "resizeactive";
        mvactive = binding "${mainMod} ALT" "moveactive";
        mvtows = binding "${mainMod} SHIFT" "movetoworkspace";

        arr = builtins.genList (n: n + 1) (9 - 1 + 1);

        acpi = lib.getExe pkgs.acpi;
      in [
        ## Master-Layout binds
        "${mainMod}, Backslash, layoutmsg, swapwithmaster master"
        #", XF86Fn, layoutmsg, addmaster"

        ''
          ${mainMod}, B, exec, ${notify-send} "$(${acpi} -b | awk '{print $3, $4}')"''

        "${mainMod}, Tab, changegroupactive, f"
        # mainmod + left / right changegroupactive f/b
        "${mainMod}, LEFT, changegroupactive, b"
        "${mainMod}, RIGHT, changegroupactive, b"


        "${mainMod}, Delete, exit"
        "${mainMod}, W, killactive"
        "${mainMod}, V, togglefloating"
        "${mainMod}, equal, fullscreen"
        # "${mainMod}, O, fakefullscreen"

        "${mainMod}, T, exec, ${
          mkHdrop {
            command = let
              kittyConfig =
                "~/${config.xdg.configFile."kitty/kitty.conf".target}";
              sedRules = [
                #"/map ctrl+t new_os_window_with_cwd/d"
                "/map ctrl+t new_os_window_with_cwd/c\\\\map ctrl+t new_window_with_cwd\\n"
                #''$ a\\map ctrl+q close_window''
              ];
              sedCommand = "sed '${builtins.concatStringsSep ";" sedRules}'";
            in "kitty --class kitty-dropterm --config <(${sedCommand} ${kittyConfig})";
            class = "kitty-dropterm";
            size = {
              width = 75;
              height = 60;
            };
            gap = 25;
            position = "top";
          }
        }"
        "${mainMod}, F, exec, ${
          mkHdrop {
            command = "${pkgs.nemo}/bin/nemo";
            class = "nemo";
            size = {
              width = 75;
              height = 60;
            };
            gap = 25;
            position = "bottom";
          }
        }"
        "${mainMod}, A, exec, ${
          mkHdrop {
            command = "firefox --no-remote -P minimal --name firefox-minimal";
            class = "firefox-minimal";
            size = {
              width = 55;
              height = 95;
            };
            gap = 250;
            position = "right";
          }
        }"
        "${mainMod}, Z, exec, ${
          mkHdrop {
            command = "${pkgs.pavucontrol}/bin/pavucontrol";
            class = "pavucontrol";
            size = {
              width = 40;
              height = 90;
            };
            gap = 25;
            position = "left";
          }
        }"

        # launcher
        #"${mainMod}, SPACE, exec, ${pkgs.ulauncher}/bin/ulauncher" # this launcher sucks
        "${mainMod}, Space, global, kando:main-menu"

        # screenshot
        ", Print, exec, ${pkgs.gscreenshot}/bin/gscreenshot -sc"
        "SHIFT, Print, exec, ${screenshot-to-text}/bin/stt"

        # misc
        ", page_down, exec, ${moveRelativeTo}/bin/mv -1 -w" # Up arrow
        ", page_up, exec, ${moveRelativeTo}/bin/mv 1 -w" # Down arrow
        ", Home, exec, ${moveRelativeTo}/bin/mv -1" # home sits where my left arrow is
        ", End, exec, ${moveRelativeTo}/bin/mv 1" # end sits where my right arrow is

        # group
        #"${mainMod}, G, togglegroup, 0"
        "${mainMod}, G, exec, ${fancyGroupScript}/bin/fancyGroup 0"
        # mod + shift + g = lockactivegroup toggle
        "${mainMod} SHIFT, G, lockactivegroup, toggle"
        # if active window is not a group then create group, else  moveoutofgroup

        # "${mainMod} SHIFT, S, toggleswallow"


        # lockscreen
        "${mainMod}, L, exec, swaylock-custom 0 120x6 10 0"
        #"${mainMod}, asciitilde, exec,  ${pkgs.kitty}/bin/kitty nx rt"

        # playerctl, music control
        ", XF86AudioNext, exec, ${pkgs.playerctl}/bin/playerctl next"
        ", XF86AudioPrev, exec, ${pkgs.playerctl}/bin/playerctl previous"
        ", XF86AudioPlay, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
        ", XF86AudioPause, exec, ${pkgs.playerctl}/bin/playerctl play-pause"
        ", XF86AudioPlayPause, exec, ${pkgs.playerctl}/bin/playerctl play-pause"

        (fancyfocus "up" "u") # keybind, and direction
        (fancyfocus "down" "d")
        (fancyfocus "left" "l")
        (fancyfocus "right" "r")

        (resizeactive "k" "0 -20")
        (resizeactive "j" "0 20")
        (resizeactive "l" "20 0")
        (resizeactive "h" "-20 0")
        (mvactive "k" "0 -20")
        (mvactive "j" "0 20")
        (mvactive "l" "20 0")
        (mvactive "h" "-20 0")
      ] ++ (map (i: ws (toString i) (toString i)) arr)
      ++ (map (i: mvtows (toString i) (toString i)) arr);

      bindle = let
        wpctl = "${pkgs.wireplumber}/bin/wpctl";
        inertia = "${
            writeNuScript "inertia" ''
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
            ''
          }/bin/inertia";
        brightness = writeNuScript "brightness" ''
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
        volumeScript = writeNuScript "volume" ''
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
        mute = "${
            writeNuScript "mute" ''
              ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle
              ${notify-bar} volbar (${pkgs.pamixer}/bin/pamixer --get-volume) (${pkgs.pamixer}/bin/pamixer --get-volume-human)
            ''
          }/bin/mute";
      in [
        ",XF86AudioMute, exec, ${mute}"
        "SUPER, XF86AudioMute, exec, ${mute}"
      ];

      bindm =
        [ "SUPER, mouse:273, resizewindow" "SUPER, mouse:272, movewindow" ];
    };
  };
}
