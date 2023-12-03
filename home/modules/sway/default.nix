{ config, pkgs, ... }:
{

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
      extraConfig = ''
        # Brightness
        bindsym XF86MonBrightnessDown exec light -U 10
        bindsym XF86MonBrightnessUp exec light -A 10

        # Volume
        bindsym XF86AudioRaiseVolume exec 'pactl set-sink-volume @DEFAULT_SINK@ +1%'
        bindsym XF86AudioLowerVolume exec 'pactl set-sink-volume @DEFAULT_SINK@ -1%'
        bindsym XF86AudioMute exec 'pactl set-sink-mute @DEFAULT_SINK@ toggle'

        # give sway a little time to startup before starting kanshi.
        # exec sleep 5; systemctl --user start kanshi.service


        set $mod Mod4
        #set $alt Mod1

        bindsym $mod+Return exec ${config.programs.kitty}/bin/kitty
      '';
    };
  };

}
