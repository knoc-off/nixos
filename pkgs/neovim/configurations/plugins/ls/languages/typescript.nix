{ ... }: {
  plugins = {
    none-ls.sources.formatting.prettier.disableTsServerFormatter = true;
    lsp.servers.ts_ls = { enable = true; };
    treesitter = { settings.ensure_installed = [ "typescript" ]; };
  };
}
