{ config, pkgs, ... }:
let

  fuzzel = "${pkgs.fuzzel}/bin/fuzzel";

in
{


  programs.swayr.enable = true;

  wayland.windowManager.sway = {
    enable = true;
    config = rec {
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

      # when press mod, run fuzzel
      bindsym $mod+space exec ${fuzzel}



    '';
  };

}
