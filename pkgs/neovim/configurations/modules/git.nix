# Git integration - gitsigns, keymaps, state synchronization
# Uses GitState as source of truth (from git-state.nix)
{lib, ...}: {
  plugins.gitsigns = {
    enable = true;
    settings.diff_opts.vertical = true;
  };

  plugins.codediff.enable = true;

  keymaps = [
    {
      mode = "n";
      key = "<leader>gm";
      action = lib.nixvim.mkRaw ''
        function()
          -- Set GitState to merge-base (source of truth)
          local merge_base = _G.GitState.set_merge_base()
          if merge_base then
            -- Sync gitsigns to use the same base
            vim.cmd('Gitsigns change_base ' .. merge_base)
            vim.notify("Comparing against merge-base: " .. merge_base:sub(1, 7), vim.log.levels.INFO)
          end
        end
      '';
      options.desc = "Diff against merge-base";
    }
    {
      mode = "n";
      key = "<leader>gM";
      action = lib.nixvim.mkRaw ''
        function()
          -- Reset GitState to HEAD (source of truth)
          _G.GitState.reset_base()
          -- Sync gitsigns
          vim.cmd('Gitsigns reset_base')
          vim.notify("Reset to HEAD", vim.log.levels.INFO)
        end
      '';
      options.desc = "Reset to HEAD";
    }
    {
      mode = "n";
      key = "<leader>gi";
      action = lib.nixvim.mkRaw ''
        function()
          -- Show current git state info
          local base = _G.GitState.get_base()
          local is_branch = _G.GitState.is_branch_diff()
          local msg = is_branch
            and ("Branch diff mode: " .. base:sub(1, 12))
            or "Working tree mode (HEAD)"
          vim.notify(msg, vim.log.levels.INFO)
        end
      '';
      options.desc = "Show git comparison info";
    }
  ];

  # Listen for git events
  autoCmd = [
    {
      event = "User";
      pattern = "GitSignsUpdate";
      callback = lib.nixvim.mkRaw ''
        function()
          -- Invalidate GitState caches when gitsigns detects changes
          _G.GitState.invalidate()
        end
      '';
      desc = "Invalidate git state on gitsigns update";
    }
  ];
}
