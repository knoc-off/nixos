# Git integration - gitsigns with hunk navigation, staging, and blame
# Uses GitState as source of truth (from git-state.nix)
{lib, ...}: {
  plugins.gitsigns = {
    enable = true;
    settings = {
      diff_opts.vertical = true;
      current_line_blame = false;
    };
  };

  keymaps = [
    # Hunk navigation
    {
      mode = "n";
      key = "]h";
      action = lib.nixvim.mkRaw "function() require('gitsigns').nav_hunk('next') end";
      options = { silent = true; desc = "Next git hunk"; };
    }
    {
      mode = "n";
      key = "[h";
      action = lib.nixvim.mkRaw "function() require('gitsigns').nav_hunk('prev') end";
      options = { silent = true; desc = "Previous git hunk"; };
    }

    # Hunk actions
    {
      mode = "n";
      key = "<leader>gs";
      action = lib.nixvim.mkRaw "function() require('gitsigns').stage_hunk() end";
      options = { silent = true; desc = "Stage hunk"; };
    }
    {
      mode = "v";
      key = "<leader>gs";
      action = lib.nixvim.mkRaw "function() require('gitsigns').stage_hunk({ vim.fn.line('.'), vim.fn.line('v') }) end";
      options = { silent = true; desc = "Stage selected lines"; };
    }
    {
      mode = "n";
      key = "<leader>gu";
      action = lib.nixvim.mkRaw "function() require('gitsigns').undo_stage_hunk() end";
      options = { silent = true; desc = "Undo stage hunk"; };
    }
    {
      mode = "n";
      key = "<leader>gr";
      action = lib.nixvim.mkRaw "function() require('gitsigns').reset_hunk() end";
      options = { silent = true; desc = "Reset hunk"; };
    }
    {
      mode = "n";
      key = "<leader>gp";
      action = lib.nixvim.mkRaw "function() require('gitsigns').preview_hunk() end";
      options = { silent = true; desc = "Preview hunk"; };
    }
    {
      mode = "n";
      key = "<leader>gb";
      action = lib.nixvim.mkRaw "function() require('gitsigns').blame_line({ full = true }) end";
      options = { silent = true; desc = "Blame line"; };
    }
    {
      mode = "n";
      key = "<leader>gd";
      action = lib.nixvim.mkRaw "function() require('gitsigns').diffthis() end";
      options = { silent = true; desc = "Diff buffer"; };
    }

    # GitState comparison controls
    {
      mode = "n";
      key = "<leader>gm";
      action = lib.nixvim.mkRaw ''
        function()
          local merge_base = _G.GitState.set_merge_base()
          if merge_base then
            vim.cmd('Gitsigns change_base ' .. merge_base)
            vim.notify("Comparing against merge-base: " .. merge_base:sub(1, 7), vim.log.levels.INFO)
          end
        end
      '';
      options = { silent = true; desc = "Diff against merge-base"; };
    }
    {
      mode = "n";
      key = "<leader>gM";
      action = lib.nixvim.mkRaw ''
        function()
          _G.GitState.reset_base()
          vim.cmd('Gitsigns reset_base')
          vim.notify("Reset to HEAD", vim.log.levels.INFO)
        end
      '';
      options = { silent = true; desc = "Reset to HEAD"; };
    }
    {
      mode = "n";
      key = "<leader>gi";
      action = lib.nixvim.mkRaw ''
        function()
          local base = _G.GitState.get_base()
          local is_branch = _G.GitState.is_branch_diff()
          local msg = is_branch
            and ("Branch diff mode: " .. base:sub(1, 12))
            or "Working tree mode (HEAD)"
          vim.notify(msg, vim.log.levels.INFO)
        end
      '';
      options = { silent = true; desc = "Show git comparison info"; };
    }
  ];

  autoCmd = [
    {
      event = "User";
      pattern = "GitSignsUpdate";
      callback = lib.nixvim.mkRaw ''
        function()
          _G.GitState.invalidate()
        end
      '';
      desc = "Invalidate git state on gitsigns update";
    }
  ];
}
