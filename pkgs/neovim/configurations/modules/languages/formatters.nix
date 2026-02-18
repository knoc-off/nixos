# Shared formatters for web-adjacent filetypes
# - biome: JS/TS/JSX/TSX, JSON
# - prettier: YAML, Markdown (biome doesn't support these yet)
{lib, pkgs, ...}: {
  plugins.conform-nvim.settings = {
    formatters_by_ft = {
      javascript = ["biome"];
      typescript = ["biome"];
      javascriptreact = ["biome"];
      typescriptreact = ["biome"];
      json = ["biome"];
      jsonc = ["biome"];
      yaml = ["prettier"];
      markdown = ["prettier"];
    };

    formatters = {
      biome = {
        command = lib.getExe pkgs.biome;
      };
      prettier = {
        command = lib.getExe pkgs.prettierd;
      };
    };
  };
}
