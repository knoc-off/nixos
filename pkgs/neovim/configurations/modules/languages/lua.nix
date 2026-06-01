# Lua development environment
# - lua_ls (Lua Language Server)
# - stylua formatting
{lib, pkgs, ...}: {
  plugins.lsp.servers.lua_ls = {
    enable = true;
    settings.Lua = {
      runtime.version = "Lua 5.3";
      workspace.checkThirdParty = false;
    };
  };

  plugins.conform-nvim.settings = {
    formatters_by_ft.lua = ["stylua"];
    formatters.stylua.command = lib.getExe pkgs.stylua;
  };
}
