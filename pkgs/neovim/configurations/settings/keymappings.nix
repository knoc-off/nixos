{ helpers, lib, ... }: {
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  keymaps = let
    normal = lib.mapAttrsToList (key: action: {
      mode = "n";
      inherit action key;
    }) {
      "<Space>" = "<NOP>";

      # Esc to clear search results
      "<esc>" = ":noh<CR>";

      # fix Y behaviour
      "Y" = "y$";

      # back and fourth between the two most recent files
      "<C-c>" = ":b#<CR>";

      # close by Ctrl+x
      "<C-x>" = ":close<CR>";

      # save by Space+s or Ctrl+s
      # "<leader>s" = ":w<CR>";
      # "<C-s>" = ":w<CR>";

      # Format
      "<leader>f" = ":lua vim.lsp.buf.format()<CR>";
      "<leader>w" = ":lua vim.lsp.buf.format()<CR>:w<CR>";

      # Repeat Last Macro
      "," = "@@";

      # navigate to left/right window
      "<leader>h" = "<C-w>h";
      "<leader>l" = "<C-w>l";

      # Press 'H', 'L' to jump to start/end of a line (first/last character)
      L = "$";
      H = "^";

      # resize with arrows
      "<C-Up>" = ":resize -2<CR>";
      "<C-Down>" = ":resize +2<CR>";
      "<C-Left>" = ":vertical resize +2<CR>";
      "<C-Right>" = ":vertical resize -2<CR>";

      # move current line up/down
      # M = Alt key
      "<M-k>" = ":move-2<CR>";
      "<M-j>" = ":move+<CR>";
    };

    visual = lib.mapAttrsToList (key: action: {
      mode = "v";
      inherit action key;
    }) {
      # Allows replacing with clipboard without replacing clip
      "p" = ''"_dP'';

      # Repeat Last Command on selected line
      "." = ":normal .<CR>";

      # better indenting
      ">" = ">gv";
      "<" = "<gv";
      "<TAB>" = ">gv";
      "<S-TAB>" = "<gv";

      # move selected line / block of text in mode
      "K" = ":m '<-2<CR>gv=gv";
      "J" = ":m '>+1<CR>gv=gv";
    };
  in helpers.keymaps.mkKeymaps { options.silent = true; } (normal ++ visual);

  plugins.which-key = {
    registrations = {
      "<leader>w" = "Format and Save";
      "<leader>h" = "Window Left";

      # For the arrow key resizing
      "<C-Up>" = "Resize Up";
      "<C-Down>" = "Resize Down";
      "<C-Left>" = "Resize Left";
      "<C-Right>" = "Resize Right";

      # For the Alt+j/k moving
      "<M-k>" = "Move Line Up";
      "<M-j>" = "Move Line Down";

      # Visual mode mappings
      "v>" = "Indent Right";
      "v<" = "Indent Left";
      "v<TAB>" = "Indent Right";
      "v<S-TAB>" = "Indent Left";
    };
  };

}
