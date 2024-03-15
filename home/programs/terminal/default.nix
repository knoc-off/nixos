{
  inputs,
  pkgs,
  libs,
  theme,
  config,
  ...
}: {
  imports = [
    ./kitty
    ./shell
    ./programs/btop.nix
  ];

  home.packages = with pkgs; [
    btop # htop but better
    tiv # terminal image viewer
    jq # json parser
    fd # better find
  ];

  programs.feh = {
    enable = true;
  };

  programs.eza = {
    enable = true;
    extraOptions = ["--group-directories-first" "--header"];
    git = true;
    icons = true;
  };

  programs.tealdeer = {
    enable = true;
    settings = {
      display = {
        compact = false;
        use_pager = true;
      };
      updates = {
        auto_update = true;
      };
    };
  };

  programs.fzf = {
    enable = true;

    colors = {
      bg = "#${theme.base01}";
      "bg+" = "#${theme.base01}";
      fg = "#${theme.base06}";
      "fg+" = "#${theme.base06}";
    };
  };

  programs.ripgrep = {
    enable = true;
    arguments = ["--hidden" "--colors=line:style:bold"];
  };

  # better cat
  programs.bat = {
    enable = true;
    config = {
      #map-syntax = [ "*.jenkinsfile:Groovy" "*.props:Java Properties" ];
      pager = "less -FR";
      theme = "TwoDark";
    };
  };
}
