{
  pkgs,
  theme,
  color-lib,
  ...
}: {
  home.packages = with pkgs; [
    btop # htop but better
    jq # json parser
    fd # better find
    qview # image viewer
  ];

  programs = {
    zoxide.enable = true;

    eza = {
      enable = true;
      extraOptions = ["--group-directories-first" "--header"];
      git = true;
    };

    tealdeer = {
      enable = true;
      settings = {
        display = {
          compact = false;
          use_pager = true;
        };
        updates = {auto_update = true;};
      };
    };

    fzf = {
      enable = true;
    };

    ripgrep = {
      enable = true;
      arguments = ["--hidden" "--colors=line:style:bold"];
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
