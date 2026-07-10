# grug-far.nvim - project-wide find & replace with a live preview buffer.
# Fills the gap left by mini.pick's live-grep, which only *finds*. Powered by
# ripgrep (already provided via mini-pick's extraPackages).
#   <leader>fR  (normal) open an empty search/replace buffer
#   <leader>fR  (visual) open pre-seeded with the current selection as the search
{lib, ...}: {
  plugins.grug-far = {
    enable = true;
    # <Esc> in normal mode closes the grug-far panel (buffer-local, so it does
    # not affect <Esc> anywhere else). Insert-mode <Esc> still just leaves insert.
    settings.keymaps.close.n = "<esc>";
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>fR";
      action = lib.nixvim.mkRaw "function() require('grug-far').open() end";
      options = { silent = true; desc = "Find & replace (project)"; };
    }
    {
      mode = "x";
      key = "<leader>fR";
      action = lib.nixvim.mkRaw "function() require('grug-far').with_visual_selection() end";
      options = { silent = true; desc = "Find & replace selection (project)"; };
    }
  ];
}
