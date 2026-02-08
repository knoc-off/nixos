{
  inputs,
  lib,
  pkgs,
  ...
}: let
  ghostty = lib.getExe pkgs.ghostty;
in {
  programs.niri = {
    #enable = lib.mkDefault true;
    package = lib.mkDefault pkgs.niri-unstable;
    settings = let
      noctalia = cmd:
        [
          "noctalia-shell"
          "ipc"
          "call"
        ]
        ++ (lib.splitString " " cmd);
    in {
      outputs = lib.mkDefault {
        "desc:BOE 0x0BCA" = {
          scale = 1.333334;
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

      binds = lib.mkDefault {
        "Mod+G".action.spawn = ghostty;
        "Mod+Space".action.spawn = noctalia "launcher toggle";
        "Mod+W".action.close-window = [];
      };
    };
  };
}
