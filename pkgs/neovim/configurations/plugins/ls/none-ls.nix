{ ... }: {
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
        prettier = {
          enable = true;
          #settings.extra_filetypes = [ "javascript" "javascriptreact" "typescript" "typescriptreact" "json" "css" "scss" "less" "html" "htmldjango" ];
          disableTsServerFormatter = true; # TypeScript
        };
        isort = {
          enable = true;
        };
        djhtml.enable = true;
        nixfmt.enable = true;
      };
      diagnostics = {
        # mypy disabled as pyright handles type checking
      };
    };
  };
}
