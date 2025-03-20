{ pkgs, ... }: {
  plugins.none-ls = {
    enable = true;
    sources = {
      formatting = {
        black = {
          enable = true;
          settings = {
            line_length = 100;
          };
        };
        isort = {
          enable = true;
        };
      };
      diagnostics = {
        flake8 = {
          enable = true;
          settings = {
            max_line_length = 100;
          };
        };
        mypy = {
          enable = true;
        };
      };
    };
  };
}
