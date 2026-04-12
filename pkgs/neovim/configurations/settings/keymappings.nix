{lib, ...}: {
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  keymaps = let
    misc = [
      { mode = "n"; key = "q:"; action = "<Nop>"; }
      {
        mode = "n";
        key = "<leader>q";
        action = lib.nixvim.mkRaw "function() vim.cmd('bdelete') end";
        options = { silent = true; desc = "Close buffer"; };
      }
      {
        mode = "n";
        key = "<leader>w";
        action = "<cmd>w<cr>";
        options = { silent = true; desc = "Save"; };
      }
    ];
    normal =
      lib.mapAttrsToList (key: action: {
        mode = "n";
        inherit action key;
      }) {
        "<Space>" = "<NOP>";

        # Esc to clear search results
        "<esc>" = ":noh<CR>";

        "Y" = "y$";

        "," = "@@";

        # Window navigation (C-hjkl is standard, avoids <leader>l conflict with lsp)
        "<C-h>" = "<C-w>h";
        "<C-l>" = "<C-w>l";
        "<C-j>" = "<C-w>j";
        "<C-k>" = "<C-w>k";

        L = "$";
        H = "^";

        # Move lines with Alt
        "<M-k>" = ":move-2<CR>";
        "<M-j>" = ":move+<CR>";

        # Half-page jump + center
        "<C-d>" = "<C-d>zz";
        "<C-u>" = "<C-u>zz";

        # Always search forward using the current @/ pattern
        "n" = ":<C-U>call search(@/, 'W')<CR>";

        # Always search backward using the current @/ pattern
        "N" = ":<C-U>call search(@/, 'bW')<CR>";

        # Yank word under cursor and set it as search pattern
        "<S-#>" = ''yiw:let @/ = @"<CR>:set hlsearch<CR>'';

        "*" = lib.nixvim.mkRaw ''
          function()
            local w = vim.fn.expand("<cword>")
            if w == nil or w == "" then return end
            local pat = [[\V\<]] .. vim.fn.escape(w, [[\]]) .. [[\>]]
            vim.fn.setreg("/", pat)
            vim.opt.hlsearch = true
            vim.fn.search(pat, "n")
          end
        '';

        "#" = lib.nixvim.mkRaw ''
          function()
            local w = vim.fn.expand("<cword>")
            if w == nil or w == "" then return end
            local pat = [[\V\<]] .. vim.fn.escape(w, [[\]]) .. [[\>]]
            vim.fn.setreg("/", pat)
            vim.opt.hlsearch = true
            vim.fn.search(pat, "nb")
          end
        '';

        "/" = lib.nixvim.mkRaw ''
          function()
            vim.ui.input({ prompt = "/" }, function(query)
              if not query or query == "" then return end
              vim.fn.setreg("/", query)
              vim.opt.hlsearch = true
              vim.fn.search(query, "n")
            end)
          end
        '';

        "?" = lib.nixvim.mkRaw ''
          function()
            vim.ui.input({ prompt = "?" }, function(query)
              if not query or query == "" then return end
              vim.fn.setreg("/", query)
              vim.opt.hlsearch = true
              vim.fn.search(query, "bn")
            end)
          end
        '';

        # Splits
        "<leader>sv" = "<cmd>vsplit<cr>";
        "<leader>sh" = "<cmd>split<cr>";
      };

    visual =
      lib.mapAttrsToList (key: action: {
        mode = "v";
        inherit action key;
      }) {
        # Paste without clobbering register
        "p" = ''"_dP'';

        "." = ":normal .<CR>";

        ">" = ">gv";
        "<" = "<gv";
        "<TAB>" = ">gv";
        "<S-TAB>" = "<gv";

        "K" = ":m '<-2<CR>gv=gv";
        "J" = ":m '>+1<CR>gv=gv";
      };

    visualStar = [
      # Visual mode: search for selected text
      {
        mode = "v";
        key = "*";
        action = lib.nixvim.mkRaw ''
          function()
            local old = vim.fn.getreg('"')
            vim.cmd('normal! y')
            local pat = [[\V]] .. vim.fn.escape(vim.fn.getreg('"'), [[\/]])
            vim.fn.setreg("/", pat)
            vim.opt.hlsearch = true
            vim.fn.setreg('"', old)
          end
        '';
        options = { silent = true; desc = "Search selection"; };
      }
    ];

    insert =
      lib.mapAttrsToList (key: action: {
        mode = "i";
        inherit action key;
      }) {
        "<C-e>" = "<End>";
        "<C-a>" = "<Home>";
      };
  in
    lib.nixvim.keymaps.mkKeymaps {options.silent = true;}
    (normal ++ visual ++ insert)
    ++ misc
    ++ visualStar;
}
