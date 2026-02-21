# Shared Git State - Single source of truth for git comparison base
# All git-related plugins (gitsigns, mini.files, neogit) should read from this
{lib, ...}: {
  extraConfigLuaPre = ''
    -- GitState: Single source of truth for git comparison
    -- Consumers: gitsigns, mini.files, (future: neogit)
    _G.GitState = {
      -- Current comparison base (nil = HEAD, or a commit/ref like "origin/main")
      base = nil,

      -- Cached merge-base with origin/main (computed on demand)
      _merge_base_cache = nil,
      _merge_base_time = 0,

      -- Get current base (returns "HEAD" if nil)
      get_base = function()
        return _G.GitState.base or "HEAD"
      end,

      -- Get merge-base with origin/main (cached for 30s)
      get_merge_base = function()
        local now = os.time()
        if _G.GitState._merge_base_cache and (now - _G.GitState._merge_base_time) < 30 then
          return _G.GitState._merge_base_cache
        end

        local result = vim.system(
          { "git", "merge-base", "HEAD", "origin/main" },
          { text = true }
        ):wait()

        if result.code == 0 then
          _G.GitState._merge_base_cache = vim.trim(result.stdout)
          _G.GitState._merge_base_time = now
          return _G.GitState._merge_base_cache
        end

        -- Fallback: try just "main"
        result = vim.system(
          { "git", "merge-base", "HEAD", "main" },
          { text = true }
        ):wait()

        if result.code == 0 then
          _G.GitState._merge_base_cache = vim.trim(result.stdout)
          _G.GitState._merge_base_time = now
          return _G.GitState._merge_base_cache
        end

        return nil
      end,

      -- Set the comparison base and notify all consumers
      set_base = function(base)
        _G.GitState.base = base
        -- Fire event for all consumers to refresh
        vim.api.nvim_exec_autocmds("User", {
          pattern = "GitStateBaseChanged",
          data = { base = base }
        })
      end,

      -- Reset to HEAD
      reset_base = function()
        _G.GitState.set_base(nil)
      end,

      -- Set to merge-base with origin/main
      set_merge_base = function()
        local merge_base = _G.GitState.get_merge_base()
        if merge_base then
          _G.GitState.set_base(merge_base)
          return merge_base
        else
          vim.notify("Could not determine merge-base with origin/main", vim.log.levels.WARN)
          return nil
        end
      end,

      -- Check if we're comparing against merge-base (not HEAD)
      is_branch_diff = function()
        return _G.GitState.base ~= nil
      end,

      -- Invalidate all caches (call when git state changes externally)
      invalidate = function()
        _G.GitState._merge_base_cache = nil
        _G.GitState._merge_base_time = 0
        vim.api.nvim_exec_autocmds("User", {
          pattern = "GitStateInvalidate",
        })
      end,
    }

    -- Auto-detect merge-base on startup (deferred)
    vim.defer_fn(function()
      if vim.fn.isdirectory(".git") == 1 or vim.fn.system("git rev-parse --git-dir 2>/dev/null"):find("%.git") then
        -- Pre-cache the merge-base
        _G.GitState.get_merge_base()
      end
    end, 100)
  '';
}
