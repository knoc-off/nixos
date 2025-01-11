{ pkgs, theme, colorLib, ... }:
let
  h2okl = colorLib.hexStrToOklch;
  oklchToHex = colorLib.oklchToHex;
  setLightness = value: color: colorLib.oklchmod.setLightness value color;

  primary = h2okl theme.primary;
  secondary = h2okl theme.secondary;
  neutral = h2okl theme.neutral;
  accent1 = h2okl theme.accent1;
  accent2 = h2okl theme.accent2;
in
{
  imports = [
    ./kitty
    ./programs/btop.nix
  ];

  home.packages = with pkgs; [
    btop # htop but better
    tiv # terminal image viewer
    jq # json parser
    fd # better find
  ];

  programs = {

    zoxide.enable = true;

    feh = { enable = true; };

    eza = {
      enable = true;
      extraOptions = [ "--group-directories-first" "--header" ];
      git = true;
    };

    tealdeer = {
      enable = true;
      settings = {
        display = {
          compact = false;
          use_pager = true;
        };
        updates = { auto_update = true; };
      };
    };

    fzf = {
      enable = true;

      #colors = {
      #  bg = "#${oklchToHex (setLightness 0.2 primary)}";
      #  "bg+" = "#${oklchToHex (setLightness 0.25 primary)}";
      #  fg = "#${oklchToHex (setLightness 0.8 neutral)}";
      #  "fg+" = "#${oklchToHex (setLightness 0.9 neutral)}";
      #};
    };

    ripgrep = {
      enable = true;
      arguments = [ "--hidden" "--colors=line:style:bold" ];
    };

    # better cat
    bat = {
      enable = true;
      config = {
        pager = "less -FR";
        theme = "TwoDark";
      };
    };
  };
}
