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
      -- Resolves the target dynamically so repos using master/trunk/etc work.
      --
      -- IMPORTANT: the integration branch (origin/main, master, ...) is tried
      -- BEFORE the branch's own upstream (@{u}). On a pushed feature branch
      -- @{u} == origin/<same-branch> ~= HEAD, so using it would yield HEAD as
      -- the "base" and show zero hunks. We also skip any candidate whose
      -- merge-base equals HEAD (nothing to diff), so the first base that is
      -- strictly behind HEAD wins.
      --   1. origin's default branch (origin/HEAD -> origin/main|master|...)
      --   2. common fallbacks (origin/main, origin/master, main, master)
      --   3. the current branch's upstream (@{u}) -- last resort, and only if
      --      it is NOT this branch's own remote (origin/<current-branch>)
      get_merge_base = function()
        local now = os.time()
        if _G.GitState._merge_base_cache and (now - _G.GitState._merge_base_time) < 30 then
          return _G.GitState._merge_base_cache
        end

        local function run(cmd)
          local result = vim.system(cmd, { text = true }):wait()
          if result.code == 0 then
            local out = vim.trim(result.stdout)
            if out ~= "" then return out end
          end
          return nil
        end

        local head = run({ "git", "rev-parse", "HEAD" })
        local branch = run({ "git", "rev-parse", "--abbrev-ref", "HEAD" })

        -- Build the ordered list of candidate refs: integration branch first.
        local candidates = {}
        local origin_head = run({ "git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
        if origin_head then table.insert(candidates, origin_head) end
        vim.list_extend(candidates, { "origin/main", "origin/master", "main", "master" })
        -- Self-upstream last, and only if it isn't this branch's own remote.
        local upstream = run({ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" })
        if upstream and upstream ~= ("origin/" .. (branch or "")) then
          table.insert(candidates, upstream)
        end

        for _, ref in ipairs(candidates) do
          if ref ~= "" then
            local merge_base = run({ "git", "merge-base", "HEAD", ref })
            -- Skip bases that equal HEAD (candidate is a descendant/equal ->
            -- nothing to diff). Keep looking for one strictly behind HEAD.
            if merge_base and merge_base ~= head then
              _G.GitState._merge_base_cache = merge_base
              _G.GitState._merge_base_time = now
              return merge_base
            end
          end
        end

        return nil
      end,

      -- Resolve the point where the current branch diverged from the
      -- integration branch (origin/main|master|...), NOT its own remote. Uses a
      -- reflog-aware fork-point against the integration target, then a plain
      -- merge-base, then falls back to get_merge_base(). Returns a commit sha,
      -- or nil if it can't be determined.
      get_branch_point = function()
        local function run(cmd)
          local result = vim.system(cmd, { text = true }):wait()
          if result.code == 0 then
            local out = vim.trim(result.stdout)
            if out ~= "" then return out end
          end
          return nil
        end

        local head = run({ "git", "rev-parse", "HEAD" })

        -- Resolve the integration branch (origin's default), not @{u}.
        local target = run({ "git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD" })
        for _, ref in ipairs({ target, "origin/main", "origin/master", "main", "master" }) do
          if ref and ref ~= "" then
            -- Reflog-aware fork point off the integration branch.
            local fork = run({ "git", "merge-base", "--fork-point", ref, "HEAD" })
            if fork and fork ~= head then return fork end
            -- Plain merge-base with the integration branch.
            local mb = run({ "git", "merge-base", "HEAD", ref })
            if mb and mb ~= head then return mb end
          end
        end

        -- Fall back to the shared heuristics (also skips base == HEAD).
        return _G.GitState.get_merge_base()
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
          vim.notify(
            "No divergence from the integration branch (nothing to diff). " ..
            "Are you on the default branch, or is it not fetched?",
            vim.log.levels.WARN
          )
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
