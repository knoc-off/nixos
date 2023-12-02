{lib, ...}: {
  programs.nixvim = {
    plugins.null-ls = {
      enable = true;
      sources = {
        diagnostics.shellcheck = {
          enable = true;
        };
        formatting = {
        nixfmt.enable = true;
        };
      };
    };
  };
}
