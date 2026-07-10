# tiny-code-action.nvim - a code-action picker with an inline diff preview,
# far nicer than the bare vim.ui.select list. Uses the `buffer` picker (no
# telescope/snacks dependency, fits our mini.pick setup) and the `delta`
# backend for syntax-highlighted diff previews of each action.
#
# Built locally via buildVimPlugin (rather than the nixneovimplugins overlay)
# because the plugin's optional `previewers.snacks` module fails the packaging
# require-check when snacks isn't present. We use picker=buffer + backend=delta,
# so that optional previewer is irrelevant -- disable the check.
{pkgs, lib, ...}: {
  extraPackages = [pkgs.delta];
  extraPlugins = [
    (pkgs.vimUtils.buildVimPlugin {
      pname = "tiny-code-action-nvim";
      version = "unstable-2026-04-25";
      src = pkgs.fetchFromGitHub {
        owner = "rachartier";
        repo = "tiny-code-action.nvim";
        rev = "0d040ed81f7953118b81cd12681fcdfcac069803";
        hash = "sha256-UF9zeO5Uujdt2MEwy2d2Lhk6JRnEN4vrEvYslv0/zaA=";
      };
      # Optional picker/previewer backends (snacks, fzf-lua, telescope) aren't
      # installed; we only use the buffer picker + delta backend.
      nvimSkipModules = ["tiny-code-action.previewers.snacks"];
      meta.description = "Code-action picker with inline diff preview";
    })
  ];

  extraConfigLua = ''
    require("tiny-code-action").setup({ picker = "buffer", backend = "delta" })
  '';

  keymaps = [
    {
      mode = ["n" "x"];
      key = "<leader>ca";
      action = lib.nixvim.mkRaw "function() require('tiny-code-action').code_action() end";
      options = { silent = true; desc = "Code action"; };
    }
  ];
}
