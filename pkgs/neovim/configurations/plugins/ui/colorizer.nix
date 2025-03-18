{ pkgs, ... }: {
  plugins.colorizer = {
    enable = true;
    settings = {
      filetypes = [
        "*"
        "!help"
      ];
      buftypes = [ "terminal" "popup" ];
    };
  };
}

