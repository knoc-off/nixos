{ config, lib, ... }: {
  programs.nixvim = {
    globals = {
      mapleader = " ";
      maplocalleader = " ";
    };

    maps = config.nixvim.helpers.mkMaps { silent = true; } {
      normal."<Space>" = "<NOP>";

      # Esc to clear search results
      normal."<esc>" = ":noh<CR>";

      # fix Y behaviour
      #normal."Y" = "y$";

      # back and fourth between the two most recent files
      normal."<C-c>" = ":b#<CR>";
      normal."<leader>c" = ":b#<CR>";

      # close by Ctrl+x
      normal."<C-x>" = ":close<CR>";

      # save by Space+s or Ctrl+s
      normal."<leader>s" = ":w<CR>";
      normal."<C-s>" = ":w<CR>";

      # Format
      normal."<leader>f" = ":lua vim.lsp.buf.format()<CR>";
      normal."<leader>w" = ":lua vim.lsp.buf.format()<CR>:w<CR>";

      # better window movement TODO change
      # normal."<C-h>" = "<C-w>h";
      # normal."<C-j>" = "<C-w>j";
      # normal."<C-k>" = "<C-w>k";
      # normal."<C-l>" = "<C-w>l";
      normal."<leader>h" = "<C-w>h";
      # normal."<leader>j" = "<C-w>j";
      # normal."<leader>k" = "<C-w>k";
      normal."<leader>l" = "<C-w>l";

      normal."<M-l>" = "<C-w>l";
      normal."<M-h>" = "<C-w>h";

      # resize with arrows
      normal."<C-Up>" = ":resize -2<CR>";
      normal."<C-Down>" = ":resize +2<CR>";
      normal."<C-Left>" = ":vertical resize +2<CR>";
      normal."<C-Right>" = ":vertical resize -2<CR>";

      # Repeat Last Macro
      normal."," = "@@";

      # Unbind pg-up/down to left/right (mainly for laptop)
      normal."<PageUp>" = "<Left>";
      normal."<PageDown>" = "<Right>";

      # Allows replacing with clipboard without replacing clip
      visual."p" = ''"_dP'';

      # better indenting
      visual.">" = ">gv";
      visual."<" = "<gv";
      visual."<TAB>" = ">gv";
      visual."<S-TAB>" = "<gv";

      # move selected line / block of text in visual mode
      visual."K" = ":m '<-2<CR>gv=gv";
      visual."J" = ":m '>+1<CR>gv=gv";

      # Repeat Last Command on selected line
      visual."." = ":normal .<CR>";

      # move current line up/down
      # M = Alt key
      normal."<M-k>" = ":move-2<CR>";
      normal."<M-j>" = ":move+<CR>";

      normal."<leader>rp" = ":!remi push<CR>";
    };
  };
}
