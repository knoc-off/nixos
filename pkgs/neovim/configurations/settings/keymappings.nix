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

      # run CodeCompanionChat toggle
      "<leader>cc" = ":CodeCompanionChat toggle<CR>";
      "<leader>co" = ":CodeCompanionChat copilot_o1<CR>";

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

      # scroll by 5 lines with Shift + Up/Down
      "<S-Up>" = ":execute \"normal! \" . v:count1 * 5 . \"k\"<CR>";
      "<S-Down>" = ":execute \"normal! \" . v:count1 * 5 . \"j\"<CR>";
    };

    visual = lib.mapAttrsToList (key: action: {
      mode = "v";
      inherit action key;
    }) {
      # Allows replacing with clipboard without replacing clip
      #"p" = ''"_dP''; # for whatever reason this breaks rust analyzer when pasting too much.

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

      # move cursor by 5 lines with Shift + Up/Down
      "<S-Up>" = "5k";
      "<S-Down>" = "5j";
    };

    # insert mode mappings
    insert = lib.mapAttrsToList (key: action: {
      mode = "i";
      inherit action key;
    }) {
      # Move cursor to the end of the line
      "<C-e>" = "<End>";

      # Move cursor to the start of the line
      "<C-a>" = "<Home>";

      # move cursor by 5 lines with Shift + Up/Down
      "<S-Up>" = "5k";
      "<S-Down>" = "5j";

    };

  in helpers.keymaps.mkKeymaps { options.silent = true; } (normal ++ visual ++ insert);

  plugins.which-key.settings.spec = [
    { "<leader>w" = { name = "Format and Save"; }; }
    { "<leader>h" = { name = "Window Left"; }; }
    { "<C-Up>" = { name = "Resize Up"; }; }
    { "<C-Down>" = { name = "Resize Down"; }; }
    { "<C-Left>" = { name = "Resize Left"; }; }
    { "<C-Right>" = { name = "Resize Right"; }; }
    { "<M-k>" = { name = "Move Line Up"; }; }
    { "<M-j>" = { name = "Move Line Down"; }; }
    { "v>" = { name = "Indent Right"; }; }
    { "v<" = { name = "Indent Left"; }; }
    { "v<TAB>" = { name = "Indent Right"; }; }
    { "v<S-TAB>" = { name = "Indent Left"; }; }
  ];

}
