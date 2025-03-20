{ pkgs, ... }: {
  # Python-specific settings
  autoCmd = [
    {
      event = "FileType";
      pattern = "python";
      command = "setlocal tabstop=4 shiftwidth=4 expandtab";
    }
  ];

  # Add Python-specific configuration
  extraConfigLua = ''
    -- Python virtual environment detection
    local venv_detector = function()
      local venv = os.getenv("VIRTUAL_ENV")
      if venv then
        vim.g.python3_host_prog = venv .. "/bin/python"
      end
    end

    -- Run detector when Neovim starts
    venv_detector()
    
    -- Configure diagnostics display for better visibility
    vim.diagnostic.config({
      virtual_text = {
        prefix = '●',
        source = "if_many",
      },
      float = {
        source = "always",
        border = "rounded",
      },
      signs = true,
      underline = true,
      update_in_insert = false,
      severity_sort = true,
    })

    -- Add Python-specific keymaps
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "python",
      callback = function()
        -- Run current Python file
        vim.api.nvim_buf_set_keymap(0, 'n', '<leader>pr', 
          ':w<CR>:split<CR>:terminal python %<CR>', 
          { noremap = true, silent = true, desc = "Run Python file" })
        
        -- Format Python file
        vim.api.nvim_buf_set_keymap(0, 'n', '<leader>pf', 
          ':lua vim.lsp.buf.format()<CR>', 
          { noremap = true, silent = true, desc = "Format Python file" })
      end
    })
  '';

  # Configure diagnostic signs and highlights
  highlight.DiagnosticError = {
    fg = "#F44747";
    underline = true;
  };
  highlight.DiagnosticWarn = {
    fg = "#FF8800";
    underline = true;
  };
  highlight.DiagnosticInfo = {
    fg = "#4FC1FF";
  };
  highlight.DiagnosticHint = {
    fg = "#BBBBBB";
  };
  
  # Highlight Python syntax elements
  highlight.pythonBuiltin = {
    fg = "#569CD6";
    italic = true;
  };
  highlight.pythonOperator = {
    fg = "#C586C0";
    bold = true;
  };
  highlight.pythonDecorator = {
    fg = "#DCDCAA";
    italic = true;
  };
}
