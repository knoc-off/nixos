{ pkgs, theme, ... }: {
  imports = [ ./kitty ./shell ./programs/btop.nix ];

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
      icons = true;
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

      colors = {
        bg = "#${theme.base01}";
        "bg+" = "#${theme.base01}";
        fg = "#${theme.base06}";
        "fg+" = "#${theme.base06}";
      };
    };

    ripgrep = {
      enable = true;
      arguments = [ "--hidden" "--colors=line:style:bold" ];
    };

    # better cat
    bat = {
      enable = true;
      config = {
        #map-syntax = [ "*.jenkinsfile:Groovy" "*.props:Java Properties" ];
        pager = "less -FR";
        theme = "TwoDark";
      };
    };
  };
}
