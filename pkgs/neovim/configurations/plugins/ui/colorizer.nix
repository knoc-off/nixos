{ pkgs, ... }: {
  plugins.nvim-colorizer = {
    enable = true;
    fileTypes = [
      "*"
      "!help"
      {
        language = "python";
        RGB = true;
        RRGGBB = true;
        names = true;
        RRGGBBAA = true;
        rgb_fn = true;
        hsl_fn = true;
        css = false;
        css_fn = true;
      }
    ];
    userDefaultOptions = {
      RGB = true;
      RRGGBB = true;
      names = true;
      RRGGBBAA = true;
      AARRGGBB = false;
      rgb_fn = true;
      hsl_fn = true;
      css = true;
      css_fn = true;
      mode = "background";
      tailwind = false;
      sass = {
        enable = false;
        parsers = { };
      };
      virtualtext = "■";
    };
    bufTypes = [ "terminal" "popup" ];
  };
}
