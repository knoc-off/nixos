{ helpers, lib, ... }: {
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  plugins.which-key.settings.spec = [
    {
      __unkeyed-1 = "<leader>";
      group = "+leader";
      icon = "󰌗 ";
      __unkeyed-2 = [
        {
          __unkeyed-1 = "c";
          group = "+code";
          icon = "󰞷 ";
          __unkeyed-2 = [
            {
              __unkeyed-1 = "c";
              __unkeyed-2 = "<cmd>CodeCompanionChat toggle<CR>";
              desc = "Toggle CodeCompanionChat";
            }
            {
              __unkeyed-1 = "o";
              __unkeyed-2 = "<cmd>CodeCompanionChat copilot_o1<CR>";
              desc = "Copilot Chat";
            }
          ];
        }
        {
          __unkeyed-1 = "f";
          __unkeyed-2 = "<cmd>lua vim.lsp.buf.format()<CR>";
          desc = "Format buffer";
        }
        {
          __unkeyed-1 = "w";
          __unkeyed-2 = "<cmd>lua vim.lsp.buf.format()<CR><cmd>w<CR>";
          desc = "Format and save";
        }
        {
          __unkeyed-1 = "a";
          __unkeyed-2 = "<cmd>lua vim.lsp.buf.code_action()<CR>";
          desc = "Code action";
        }
        {
          __unkeyed-1 = "h";
          __unkeyed-2 = "<C-w>h";
          desc = "Move to left window";
        }
        {
          __unkeyed-1 = "l";
          __unkeyed-2 = "<C-w>l";
          desc = "Move to right window";
        }
      ];
    }
    {
      __unkeyed-1 = "<C-Up>";
      __unkeyed-2 = "<cmd>resize -2<CR>";
      desc = "Resize window up";
    }
    {
      __unkeyed-1 = "<C-Down>";
      __unkeyed-2 = "<cmd>resize +2<CR>";
      desc = "Resize window down";
    }
    {
      __unkeyed-1 = "<C-Left>";
      __unkeyed-2 = "<cmd>vertical resize +2<CR>";
      desc = "Resize window left";
    }
    {
      __unkeyed-1 = "<C-Right>";
      __unkeyed-2 = "<cmd>vertical resize -2<CR>";
      desc = "Resize window right";
    }
    {
      __unkeyed-1 = "<M-k>";
      __unkeyed-2 = "<cmd>move-2<CR>";
      desc = "Move line up";
    }
    {
      __unkeyed-1 = "<M-j>";
      __unkeyed-2 = "<cmd>move+<CR>";
      desc = "Move line down";
    }
    {
      __unkeyed-1 = "<S-Up>";
      __unkeyed-2 = "<cmd>execute \"normal! \" . v:count1 * 5 . \"k\"<CR>";
      desc = "Scroll up 5 lines";
    }
    {
      __unkeyed-1 = "<S-Down>";
      __unkeyed-2 = "<cmd>execute \"normal! \" . v:count1 * 5 . \"j\"<CR>";
      desc = "Scroll down 5 lines";
    }
    {
      __unkeyed-1 = "<C-c>";
      __unkeyed-2 = "<cmd>b#<CR>";
      desc = "Switch to last buffer";
    }
    {
      __unkeyed-1 = "<C-x>";
      __unkeyed-2 = "<cmd>close<CR>";
      desc = "Close window";
    }
    {
      __unkeyed-1 = "<C-e>";
      __unkeyed-2 = "<End>";
    }
    {
      __unkeyed-1 = "<C-a>";
      __unkeyed-2 = "<Home>";
    }
    {
      __unkeyed-1 = "L";
      __unkeyed-2 = "$";
    }
    {
      __unkeyed-1 = "H";
      __unkeyed-2 = "^";
    }
    {
      __unkeyed-1 = ",";
      __unkeyed-2 = "@@";
    }
    {
      __unkeyed-1 = "Y";
      __unkeyed-2 = "y$";
    }
    {
      __unkeyed-1 = "<esc>";
      __unkeyed-2 = "<cmd>noh<CR>";
    }
  ];

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

      # Accept LSP code action for the current line
      "<leader>a" = ":lua vim.lsp.buf.code_action()<CR>";

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

}
