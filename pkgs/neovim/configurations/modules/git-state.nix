# Shared Git State - Single source of truth for git comparison base
# All git-related plugins (gitsigns, mini.files, neogit) should read from this
{lib, ...}: {
  extraConfigLuaPre = ''
    -- GitState: Single source of truth for git comparison
    -- Consumers: gitsigns, mini.files, (future: neogit)
    _G.GitState = {
      -- Current comparison base (nil = HEAD, or a commit/ref like "origin/main")
      base = nil,

      -- Cached merge-base with the default branch (computed on demand)
      _merge_base_cache = nil,
      _merge_base_time = 0,

      -- Get current base (returns "HEAD" if nil)
      get_base = function()
        return _G.GitState.base or "HEAD"
      end,

      -- Get merge-base with the branch's integration target (cached for 30s).
      -- Resolves the target dynamically so repos using master/trunk/etc work:
      --   1. the current branch's upstream (@{u})
      --   2. origin's default branch (origin/HEAD)
      --   3. common fallbacks (origin/main, origin/master, main, master)
      get_merge_base = function()
        local now = os.time()
        if _G.GitState._merge_base_cache and (now - _G.GitState._merge_base_time) < 30 then
          return _G.GitState._merge_base_cache
        end

        local function run(cmd)
          local result = vim.system(cmd, { text = true }):wait()
          if result.code == 0 then
            return vim.trim(result.stdout)
          end
          return nil
        end

        -- Build the ordered list of candidate refs to compare against
        local candidates = {}
        local upstream = run({ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" })
        if upstream then table.insert(candidates, upstream) end
        local origin_head = run({ "git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
        if origin_head then table.insert(candidates, origin_head) end
        vim.list_extend(candidates, { "origin/main", "origin/master", "main", "master" })

        for _, ref in ipairs(candidates) do
          if ref ~= "" then
            local merge_base = run({ "git", "merge-base", "HEAD", ref })
            if merge_base then
              _G.GitState._merge_base_cache = merge_base
              _G.GitState._merge_base_time = now
              return merge_base
            end
          end
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
          vim.notify("Could not determine merge-base with the default branch", vim.log.levels.WARN)
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
      if vim.fn.isdirectory(".git") == 1 then
        _G.GitState.get_merge_base()
        return
      end
      -- Async fallback for repos where .git is a file (worktrees, submodules)
      vim.system({ "git", "rev-parse", "--git-dir" }, { text = true }, function(result)
        if result.code == 0 then
          vim.schedule(function() _G.GitState.get_merge_base() end)
        end
      end)
    end, 100)
  '';
}
