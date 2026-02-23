# C/C++ development environment
# - clangd via clangd-extensions (AST, memory usage, hierarchy)
# - clang-format formatting
{lib, pkgs, ...}: {
  plugins.clangd-extensions = {
    enable = true;
    enableOffsetEncodingWorkaround = true; # Fixes "multiple different client offset_encodings" warning
  };

  plugins.lsp.servers.clangd = {
    enable = true;
    cmd = [
      "clangd"
      "--background-index"
      "--clang-tidy"
      "--completion-style=detailed"
      "--header-insertion=iwyu"
      "--fallback-style=llvm"
    ];
  };

  plugins.conform-nvim.settings = {
    formatters_by_ft.c = ["clang-format"];
    formatters_by_ft.cpp = ["clang-format"];
    formatters."clang-format" = {
      command = lib.getExe' pkgs.clang-tools "clang-format";
    };
  };
}