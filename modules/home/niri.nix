{
  inputs,
  lib,
  pkgs,
  ...
}: {
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

      binds = lib.mkDefault {
        "Mod+G".action.spawn = "ghostty";
        "Mod+Space".action.spawn = noctalia "launcher toggle";
        "Mod+W".action.close-window = [];
      };
    };
  };
}
