{
  inputs,
  lib,
  pkgs,
  config,
  ...
}: let
  ghostty = lib.getExe pkgs.ghostty;
  noctaliaCmd = lib.getExe config.programs.noctalia-shell.package;
in {
  programs.niri = {
    #enable = lib.mkDefault true;
    package = lib.mkDefault pkgs.niri-unstable;

    settings = let
      noctalia = cmd:
        [
          noctaliaCmd
          "ipc"
          "call"
        ]
        ++ (lib.splitString " " cmd);
    in {
      # Request clients to not use client-side decorations (no GTK title bars)
      prefer-no-csd = true;

      layout = {
        gaps = 6;
      };

      window-rules = [
        {
          geometry-corner-radius = {
            top-left = 12.0;
            top-right = 8.0;
            bottom-left = 12.0;
            bottom-right = 8.0;
          };
          clip-to-geometry = true;
        }
      ];

      outputs = lib.mkDefault {
        "desc:BOE 0x0BCA" = {
          scale = 1.1;
        };
        "desc:Samsung Electric Company S27F350" = {
          scale = 1;
        };
      };

      # Touchpad settings - 3-finger swipe gestures are built-in to niri
      # and work automatically when the touchpad is enabled
      input = {
        touchpad = {
          enable = true;
          tap = true;
          natural-scroll = true;
        };

        focus-follows-mouse = {
          max-scroll-amount = "30%";
          enable = true;
        };
      };

      # Spawn ghostty on startup
      spawn-at-startup = [
        {argv = [ghostty];}
      ];

      binds = let
        spawn = cmd: {action.spawn = cmd;};
        spawnSh = cmd: {action.spawn = ["sh" "-c" cmd];};
        locked = attrs: attrs // {allow-when-locked = true;};
      in
        lib.mkDefault {
          # Custom binds
          "Mod+G".action.spawn = ghostty;
          "Mod+Space".action.spawn = noctalia "launcher toggle";

          # Show hotkey overlay
          "Mod+Shift+Slash".action.show-hotkey-overlay = [];

          # Program launchers
          # "Mod+T".action.spawn = "alacritty";
          "Mod+D".action.spawn = "fuzzel";
          "Super+Alt+L".action.spawn = noctalia "lockScreen lock";

          # Screen reader toggle
          "Super+Alt+S" = locked (spawnSh "pkill orca || exec orca");

          # Volume keys (PipeWire/WirePlumber)
          "XF86AudioRaiseVolume" = locked (spawnSh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0");
          "XF86AudioLowerVolume" = locked (spawnSh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-");
          "XF86AudioMute" = locked (spawnSh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle");
          "XF86AudioMicMute" = locked (spawnSh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle");

          # Media keys (playerctl)
          "XF86AudioPlay" = locked (spawnSh "playerctl play-pause");
          "XF86AudioStop" = locked (spawnSh "playerctl stop");
          "XF86AudioPrev" = locked (spawnSh "playerctl previous");
          "XF86AudioNext" = locked (spawnSh "playerctl next");

          # Brightness keys
          "XF86MonBrightnessUp" = locked {action.spawn = ["brightnessctl" "--class=backlight" "set" "+10%"];};
          "XF86MonBrightnessDown" = locked {action.spawn = ["brightnessctl" "--class=backlight" "set" "10%-"];};

          # Overview
          "Mod+O".action.toggle-overview = [];

          # Close window
          "Mod+Q".action.close-window = [];

          # Focus navigation (arrows)
          "Mod+Left".action.focus-column-left = [];
          "Mod+Down".action.focus-window-down = [];
          "Mod+Up".action.focus-window-up = [];
          "Mod+Right".action.focus-column-right = [];

          # Focus navigation (vim keys)
          "Mod+H".action.focus-column-left = [];
          "Mod+J".action.focus-window-down = [];
          "Mod+K".action.focus-window-up = [];
          "Mod+L".action.focus-column-right = [];

          # Move windows (arrows)
          "Mod+Ctrl+Left".action.move-column-left = [];
          "Mod+Ctrl+Down".action.move-window-down = [];
          "Mod+Ctrl+Up".action.move-window-up = [];
          "Mod+Ctrl+Right".action.move-column-right = [];

          # Move windows (vim keys)
          "Mod+Ctrl+H".action.move-column-left = [];
          "Mod+Ctrl+J".action.move-window-down = [];
          "Mod+Ctrl+K".action.move-window-up = [];
          "Mod+Ctrl+L".action.move-column-right = [];

          # First/last column
          "Mod+Home".action.focus-column-first = [];
          "Mod+End".action.focus-column-last = [];
          "Mod+Ctrl+Home".action.move-column-to-first = [];
          "Mod+Ctrl+End".action.move-column-to-last = [];

          # Monitor focus (arrows)
          "Mod+Shift+Left".action.focus-monitor-left = [];
          "Mod+Shift+Down".action.focus-monitor-down = [];
          "Mod+Shift+Up".action.focus-monitor-up = [];
          "Mod+Shift+Right".action.focus-monitor-right = [];

          # Monitor focus (vim keys)
          "Mod+Shift+H".action.focus-monitor-left = [];
          "Mod+Shift+J".action.focus-monitor-down = [];
          "Mod+Shift+K".action.focus-monitor-up = [];
          "Mod+Shift+L".action.focus-monitor-right = [];

          # Move to monitor (arrows)
          "Mod+Shift+Ctrl+Left".action.move-column-to-monitor-left = [];
          "Mod+Shift+Ctrl+Down".action.move-column-to-monitor-down = [];
          "Mod+Shift+Ctrl+Up".action.move-column-to-monitor-up = [];
          "Mod+Shift+Ctrl+Right".action.move-column-to-monitor-right = [];

          # Move to monitor (vim keys)
          "Mod+Shift+Ctrl+H".action.move-column-to-monitor-left = [];
          "Mod+Shift+Ctrl+J".action.move-column-to-monitor-down = [];
          "Mod+Shift+Ctrl+K".action.move-column-to-monitor-up = [];
          "Mod+Shift+Ctrl+L".action.move-column-to-monitor-right = [];

          # Workspace navigation
          "Mod+Page_Down".action.focus-workspace-down = [];
          "Mod+Page_Up".action.focus-workspace-up = [];
          "Mod+U".action.focus-workspace-down = [];
          "Mod+I".action.focus-workspace-up = [];
          "Mod+Ctrl+Page_Down".action.move-column-to-workspace-down = [];
          "Mod+Ctrl+Page_Up".action.move-column-to-workspace-up = [];
          "Mod+Ctrl+U".action.move-column-to-workspace-down = [];
          "Mod+Ctrl+I".action.move-column-to-workspace-up = [];

          # Move workspace position
          "Mod+Shift+Page_Down".action.move-workspace-down = [];
          "Mod+Shift+Page_Up".action.move-workspace-up = [];
          "Mod+Shift+U".action.move-workspace-down = [];
          "Mod+Shift+I".action.move-workspace-up = [];

          # Mouse wheel workspace navigation
          "Mod+WheelScrollDown".action.focus-workspace-down = [];
          "Mod+WheelScrollUp".action.focus-workspace-up = [];
          "Mod+Ctrl+WheelScrollDown".action.move-column-to-workspace-down = [];
          "Mod+Ctrl+WheelScrollUp".action.move-column-to-workspace-up = [];

          # Mouse wheel column navigation
          "Mod+WheelScrollRight".action.focus-column-right = [];
          "Mod+WheelScrollLeft".action.focus-column-left = [];
          "Mod+Ctrl+WheelScrollRight".action.move-column-right = [];
          "Mod+Ctrl+WheelScrollLeft".action.move-column-left = [];

          # Shift+wheel for horizontal
          "Mod+Shift+WheelScrollDown".action.focus-column-right = [];
          "Mod+Shift+WheelScrollUp".action.focus-column-left = [];
          "Mod+Ctrl+Shift+WheelScrollDown".action.move-column-right = [];
          "Mod+Ctrl+Shift+WheelScrollUp".action.move-column-left = [];

          # Workspace by index
          "Mod+1".action.focus-workspace = 1;
          "Mod+2".action.focus-workspace = 2;
          "Mod+3".action.focus-workspace = 3;
          "Mod+4".action.focus-workspace = 4;
          "Mod+5".action.focus-workspace = 5;
          "Mod+6".action.focus-workspace = 6;
          "Mod+7".action.focus-workspace = 7;
          "Mod+8".action.focus-workspace = 8;
          "Mod+9".action.focus-workspace = 9;

          # Move to workspace by index
          "Mod+Ctrl+1".action.move-column-to-workspace = 1;
          "Mod+Ctrl+2".action.move-column-to-workspace = 2;
          "Mod+Ctrl+3".action.move-column-to-workspace = 3;
          "Mod+Ctrl+4".action.move-column-to-workspace = 4;
          "Mod+Ctrl+5".action.move-column-to-workspace = 5;
          "Mod+Ctrl+6".action.move-column-to-workspace = 6;
          "Mod+Ctrl+7".action.move-column-to-workspace = 7;
          "Mod+Ctrl+8".action.move-column-to-workspace = 8;
          "Mod+Ctrl+9".action.move-column-to-workspace = 9;

          # Window column management
          "Mod+BracketLeft".action.consume-or-expel-window-left = [];
          "Mod+BracketRight".action.consume-or-expel-window-right = [];
          "Mod+Comma".action.consume-window-into-column = [];
          "Mod+Period".action.expel-window-from-column = [];

          # Layout and sizing
          "Mod+R".action.switch-preset-column-width = [];
          "Mod+Shift+R".action.switch-preset-window-height = [];
          "Mod+Ctrl+R".action.reset-window-height = [];
          "Mod+F".action.maximize-column = [];
          "Mod+Shift+F".action.fullscreen-window = [];
          "Mod+M".action.maximize-window-to-edges = [];
          "Mod+Ctrl+F".action.expand-column-to-available-width = [];
          # "Mod+C".action.center-column = [];
          "Mod+Ctrl+C".action.center-visible-columns = [];

          # Width/height adjustments
          # "Mod+Minus".action.set-column-width = "-10%";
          # "Mod+Equal".action.set-column-width = "+10%";
          # "Mod+Shift+Minus".action.set-window-height = "-10%";
          # "Mod+Shift+Equal".action.set-window-height = "+10%";

          # Floating windows
          "Mod+Shift+V".action.toggle-window-floating = [];
          #"Mod+Shift+V".action.switch-focus-between-floating-and-tiling = [];

          # Tabbed display
          # "Mod+W".action.toggle-column-tabbed-display = [];

          # Screenshots
          "Print".action.screenshot = [];
          "Ctrl+Print".action.screenshot-screen = [];
          "Alt+Print".action.screenshot-window = [];

          # Keyboard shortcuts inhibitor
          "Mod+Escape".action.toggle-keyboard-shortcuts-inhibit = [];

          # Quit and power
          "Mod+Shift+E".action.quit = [];
          "Ctrl+Alt+Delete".action.quit = [];
          "Mod+Shift+P".action.power-off-monitors = [];
        };
    };
  };

  services.swayidle = {
    enable = true;
    events = [
      {
        event = "before-sleep";
        command = "${noctaliaCmd} ipc call lockScreen lock";
      }
      {
        event = "lock";
        command = "${noctaliaCmd} ipc call lockScreen lock";
      }
    ];
    timeouts = [
      {
        timeout = 300;
        command = "${noctaliaCmd} ipc call lockScreen lock";
      }
      {
        timeout = 600;
        command = "niri msg action power-off-monitors";
      }
      {
        timeout = 1800; # 30 minutes
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
  };
}
