# prompt-reference.nvim - stage code references (each with its own prompt) into
# a review, then copy the whole bundle formatted for pasting into an LLM.
# https://github.com/r10a/prompt-reference.nvim
#
# Built locally via buildVimPlugin (same pattern as tiny-code-action). The
# plugin's own default keymaps are NOT used (keymaps = false) because they
# collide with our setup: its visual <CR> clashes with treesitter
# incremental_selection, and its <Tab><Tab> clashes with blink snippet jumping.
# We bind our own under the free <leader>a ("AI review") namespace instead.
#
#   <leader>aa  (visual) add the selection to the review (prompts for text)
#   <leader>ar  (normal) open the review window
#   <leader>ac  (normal) copy the review to the clipboard and clear it
{pkgs, lib, ...}: {
  whichKeyGroups = [{__unkeyed = "<leader>a"; group = "AI review";}];

  extraPlugins = [
    (pkgs.vimUtils.buildVimPlugin {
      pname = "prompt-reference-nvim";
      version = "unstable-2025-06-01";
      src = pkgs.fetchFromGitHub {
        owner = "r10a";
        repo = "prompt-reference.nvim";
        rev = "dff576e84ca850431f66c10f28834a830990b6e8";
        hash = "sha256-p9QG2Tqv3ySadsv3+TMLOohp5QAeql+LuATIzwN3Lkc=";
      };
      meta = {
        description = "Stage code references with prompts into a review, copy for an LLM";
        homepage = "https://github.com/r10a/prompt-reference.nvim";
      };
    })
  ];

  extraConfigLua = ''
    require("prompt-reference").setup({
      output_style = "xml", -- xml parses more reliably for Claude
      keymaps = false, -- bind our own below to avoid collisions
    })
  '';

  keymaps = [
    {
      mode = "x";
      key = "<leader>aa";
      action = lib.nixvim.mkRaw "function() require('prompt-reference').add_selection() end";
      options = { silent = true; desc = "Add selection to review"; };
    }
    {
      mode = "n";
      key = "<leader>ar";
      action = lib.nixvim.mkRaw "function() require('prompt-reference').review() end";
      options = { silent = true; desc = "Open review"; };
    }
    {
      mode = "n";
      key = "<leader>ac";
      action = lib.nixvim.mkRaw "function() require('prompt-reference').copy_all() end";
      options = { silent = true; desc = "Copy review"; };
    }
  ];
}
