{lib, ...}: {
  plugins.gitsigns = {
    enable = true;
    settings.diff_opts.vertical = true;
  };

  plugins.codediff.enable = true;

  keymaps = [
    { mode = "n"; key = "<leader>gm"; action = ":Gitsigns change_base origin/main~<CR>"; options.desc = "Diff against merge-base"; }
    { mode = "n"; key = "<leader>gM"; action = ":Gitsigns reset_base<CR>"; options.desc = "Reset to HEAD"; }
  ];
}
