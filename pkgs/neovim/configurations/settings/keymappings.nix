{lib, ...}: {
  globals = {
    mapleader = " ";
    maplocalleader = " ";
  };

  keymaps = let
    # Disable arrow keys - use hjkl instead
    arrowWarning = key: hint:
      lib.nixvim.mkRaw ''
        function()
          vim.notify("Use '${hint}' instead of <${key}>", vim.log.levels.WARN)
        end
      '';

    disabledArrows = lib.concatMap (mode: [
      {
        inherit mode;
        key = "<Up>";
        action = arrowWarning "Up" "k";
        options = {
          silent = true;
          desc = "Disabled - use k";
        };
      }
      {
        inherit mode;
        key = "<Down>";
        action = arrowWarning "Down" "j";
        options = {
          silent = true;
          desc = "Disabled - use j";
        };
      }
      {
        inherit mode;
        key = "<Left>";
        action = arrowWarning "Left" "h";
        options = {
          silent = true;
          desc = "Disabled - use h";
        };
      }
      {
        inherit mode;
        key = "<Right>";
        action = arrowWarning "Right" "l";
        options = {
          silent = true;
          desc = "Disabled - use l";
        };
      }
    ]) ["n" "v" "i"];

    normal =
      lib.mapAttrsToList (key: action: {
        mode = "n";
        inherit action key;
      }) {
        "<Space>" = "<NOP>";

        # Esc to clear search results
        "<esc>" = ":noh<CR>";

        "Y" = "y$";

        "<leader>a" = ":lua vim.lsp.buf.code_action()<CR>";

        # LSP functions without telescope equivalents
        "<leader>lh" = ":lua vim.lsp.buf.hover()<CR>";
        "<leader>lS" = ":lua vim.lsp.buf.signature_help()<CR>";
        "<leader>ln" = ":lua vim.lsp.buf.rename()<CR>";
        "<leader>lf" = ":lua vim.lsp.buf.format()<CR>";

        "," = "@@";

        "<leader>h" = "<C-w>h";
        "<leader>l" = "<C-w>l";

        L = "$";
        H = "^";

        # M = Alt key
        "<M-k>" = ":move-2<CR>";
        "<M-j>" = ":move+<CR>";

        # Always search forward using the current @/ pattern.
        "n" = ":<C-U>call search(@/, 'W')<CR>";

        # Always search backward using the current @/ pattern.
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
            vim.fn.search(pat, "n")   -- establishes forward search context without moving
          end
        '';

        "#" = lib.nixvim.mkRaw ''
          function()
            local w = vim.fn.expand("<cword>")
            if w == nil or w == "" then return end
            local pat = [[\V\<]] .. vim.fn.escape(w, [[\]]) .. [[\>]]
            vim.fn.setreg("/", pat)
            vim.opt.hlsearch = true
            vim.fn.search(pat, "nb")  -- establishes backward search context without moving
          end
        '';

        "/" = lib.nixvim.mkRaw ''
          function()
            vim.ui.input({ prompt = "/" }, function(query)
              if not query or query == "" then return end
              vim.fn.setreg("/", query)
              vim.opt.hlsearch = true
              vim.fn.search(query, "n") -- 'n' = don't move cursor
            end)
          end
        '';

        # No-jump search backward
        "?" =
          lib.nixvim.mkRaw
          "function() local query = vim.fn.input('?'); if query ~= '' then vim.fn.setreg('/', query); vim.fn.search(query, 'bn'); vim.opt.hlsearch = true; end end";
      };

    visual =
      lib.mapAttrsToList (key: action: {
        mode = "v";
        inherit action key;
      }) {
        # Allows replacing with clipboard without replacing clip
        "p" = ''
          "_dP''; # for whatever reason this breaks rust analyzer when pasting too much.

        "." = ":normal .<CR>";

        ">" = ">gv";
        "<" = "<gv";
        "<TAB>" = ">gv";
        "<S-TAB>" = "<gv";

        "K" = ":m '<-2<CR>gv=gv";
        "J" = ":m '>+1<CR>gv=gv";
      };

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
    ++ disabledArrows;
}
