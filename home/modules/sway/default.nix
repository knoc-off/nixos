{ config, lib, pkgs, ... }:
let

  fuzzel = "${pkgs.fuzzel}/bin/fuzzel";

in
{


  programs.swayr.enable = true;

  wayland.windowManager.sway = {
    enable = true;


    config = rec {
      gaps = {
        inner = 10;
        outer = 0;
        smartGaps = true;
        smartBorders = "on";
      };

      input = {
        "type:touchpad" = {
          accel_profile = "adaptive";
          drag = "enabled";
          drag_lock = "disabled";
          dwt = "enabled";
          left_handed = "disabled";
          middle_emulation = "enabled";
          pointer_accel = "0.3";
          scroll_method = "two_finger";
          scroll_factor = "0.5";
          natural_scroll = "enabled";
          tap = "enabled";
        };

        "type:keyboard" = {
          xkb_layout = "us";
          #xkb_variant = "dvorak";
          #xkb_options = "compose:ralt";
          xkb_options = "caps:escape";
        };
      };


      keybindings =
        let
          mod = config.wayland.windowManager.sway.config.modifier;
        in
        lib.mkOptionDefault {
          "${mod}+space" = "exec ${fuzzel}";





          # Keybinds
        };
      modifier = "Mod4";
      # Use kitty as default terminal
      terminal = "kitty";
      startup = [
        # Launch Firefox on start
        { command = "firefox"; }
      ];
    };
    extraConfig = ''
      set $mod Mod4
      #set $alt Mod1

      # Brightness
      bindsym XF86MonBrightnessDown exec light -U 10
      bindsym XF86MonBrightnessUp exec light -A 10

      # Volume
      bindsym XF86AudioRaiseVolume exec 'pactl set-sink-volume @DEFAULT_SINK@ +1%'
      bindsym XF86AudioLowerVolume exec 'pactl set-sink-volume @DEFAULT_SINK@ -1%'
      bindsym XF86AudioMute exec 'pactl set-sink-mute @DEFAULT_SINK@ toggle'

      # give sway a little time to startup before starting kanshi.
      # exec sleep 5; systemctl --user start kanshi.service




    '';
  };

}
