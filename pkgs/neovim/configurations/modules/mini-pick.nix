# Fuzzy finder via mini.pick + mini.extra (replaces telescope)
# Also routes vim.ui.select (code actions, rust target, session pickers) through
# mini.pick for a consistent picker UX across the whole config.
{lib, pkgs, ...}: {
  whichKeyGroups = [{__unkeyed = "<leader>f"; group = "Find";}];

  # Guarantee the CLI tools mini.pick shells out to are always present,
  # independent of the ambient system PATH. mini.pick prefers rg > fd > git.
  extraPackages = [pkgs.ripgrep pkgs.fd];

  plugins.mini.modules = {
    pick = {
      # Match the telescope muscle memory: Ctrl-j/k to move the selection.
      mappings = {
        move_down = "<C-j>";
        move_up = "<C-k>";
      };
      # Span the full terminal width (edge-to-edge); leave default height/anchor.
      # Callable so it recomputes on terminal resize.
      window.config = lib.nixvim.mkRaw ''
        function()
          return { width = vim.o.columns, col = 0 }
        end
      '';
    };
    # Registers the extended pickers (oldfiles, diagnostic, lsp, ...) into
    # MiniPick.registry, also exposing them as `:Pick <name>` for discovery.
    extra = {};
  };

  extraConfigLua = ''
    -- Route vim.ui.select through mini.pick (code actions, session pickers, etc.)
    vim.ui.select = require('mini.pick').ui_select

    -- Picker over files changed in a given git diff range. Items are file paths,
    -- so mini.pick's default file preview (<Tab>) and open-on-choose apply.
    -- `rev` is any diff argument: "abc123...HEAD", "HEAD~4", "main", etc.
    -- When `rev` is nil, shows only uncommitted working-tree changes.
    _G.MiniPickGitChanged = function(rev, name)
      local root = vim.fs.root(0, '.git') or vim.fn.getcwd()
      local function lines(args)
        local cmd = vim.list_extend({ 'git', '-C', root, 'diff', '--name-only', '--relative' }, args)
        local res = vim.system(cmd, { text = true }):wait()
        if res.code ~= 0 then return {} end
        return vim.split(vim.trim(res.stdout), '\n', { trimempty = true })
      end

      -- Union of committed-range changes and uncommitted working-tree changes,
      -- deduplicated while preserving order.
      local seen, items = {}, {}
      local collected = {}
      if rev then vim.list_extend(collected, lines({ rev })) end
      vim.list_extend(collected, lines({})) -- uncommitted (unstaged) changes
      for _, f in ipairs(collected) do
        if not seen[f] then seen[f] = true; items[#items + 1] = f end
      end

      if #items == 0 then
        vim.notify('No changed files for ' .. (rev or 'working tree'), vim.log.levels.INFO)
        return
      end

      require('mini.pick').start({
        source = { items = items, name = name or ('Git changed (' .. (rev or 'working tree') .. ')'), cwd = root },
      })
    end

    -- Picker over individual git hunks, diffed against a base revision so it
    -- stays consistent with gitsigns / <leader>gd / <leader>gl (all read
    -- _G.GitState.get_base()). Each item is one hunk: searchable, <Tab> shows
    -- the hunk with `diff` syntax, <CR> jumps to its first changed line.
    --
    -- The patch->hunk-item parser below is ported from mini.extra's private
    -- `H.git_difflines_to_hunkitems` (mini.extra exposes `git_hunks` but with no
    -- revision knob, so it can't honor GitState.base). Re-sync if it changes.
    local function difflines_to_hunkitems(lines, n_context)
      local header_pattern = '^diff %-%-git'
      local hunk_pattern = '^@@ %-%d+,?%d* %+(%d+),?%d* @@'
      local from_path_pattern = '^%-%-%- [ai]/(.*)$'
      local to_path_pattern = '^%+%+%+ [bw]/(.*)$'

      local cur_header, cur_path, is_in_hunk = {}, nil, false
      local items = {}
      for _, l in ipairs(lines) do
        if l:find(header_pattern) ~= nil then
          is_in_hunk = false
          cur_header = {}
        end
        local path_match = l:match(to_path_pattern) or l:match(from_path_pattern)
        if path_match ~= nil and not is_in_hunk then cur_path = path_match end
        local hunk_start = l:match(hunk_pattern)
        if hunk_start ~= nil then
          is_in_hunk = true
          table.insert(items, { path = cur_path, lnum = tonumber(hunk_start), header = vim.deepcopy(cur_header), hunk = {} })
        end
        if is_in_hunk then
          table.insert(items[#items].hunk, l)
        else
          table.insert(cur_header, l)
        end
      end

      -- Point lnum at the hunk's first added/removed line.
      for _, item in ipairs(items) do
        for i = 2, #item.hunk do
          if item.hunk[i]:find('^[+-]') ~= nil then
            item.lnum = item.lnum + i - 2
            break
          end
        end
      end

      -- Aligned display text: "<path> │ <coords> │ <title>".
      local path_width, coords_width, parts = 0, 0, {}
      for i, item in ipairs(items) do
        local coords, title = item.hunk[1]:match('@@ (.-) @@ ?(.*)$')
        coords, title = coords or "", title or ""
        parts[i] = { item.path, coords, title }
        path_width = math.max(path_width, vim.fn.strchars(item.path))
        coords_width = math.max(coords_width, vim.fn.strchars(coords))
      end
      local function pad(s, w) return s .. string.rep(' ', w - vim.fn.strchars(s)) end
      for i, item in ipairs(items) do
        item.text = string.format('%s │ %s │ %s', pad(parts[i][1], path_width), pad(parts[i][2], coords_width), parts[i][3])
      end

      return items
    end

    _G.MiniPickGitHunks = function(base)
      local root = vim.fs.root(0, '.git') or vim.fn.getcwd()
      base = base or _G.GitState.get_base()
      local n_context = 3
      local cmd = { 'git', '-C', root, 'diff', '--patch', '--unified=' .. n_context, '--color=never', base, '--', '.' }
      local res = vim.system(cmd, { text = true }):wait()
      if res.code ~= 0 then
        vim.notify('git diff failed for base ' .. tostring(base), vim.log.levels.WARN)
        return
      end
      local items = difflines_to_hunkitems(vim.split(res.stdout or "", '\n'), n_context)
      if #items == 0 then
        vim.notify('No hunks vs ' .. tostring(base), vim.log.levels.INFO)
        return
      end

      local preview = function(buf_id, item)
        if not pcall(vim.treesitter.start, buf_id, 'diff') then
          vim.bo[buf_id].syntax = 'diff'
        end
        local lines = vim.deepcopy(item.header)
        vim.list_extend(lines, item.hunk)
        vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
      end

      require('mini.pick').start({
        source = { items = items, name = 'Git hunks (vs ' .. tostring(base) .. ')', cwd = root, preview = preview },
      })
    end
  '';

  keymaps = let
    mk = key: fn: desc: {
      mode = "n";
      inherit key;
      action = lib.nixvim.mkRaw "function() ${fn} end";
      options = {
        silent = true;
        inherit desc;
      };
    };
  in [
    (mk "<leader>ff" "require('mini.pick').builtin.files()" "Find files")
    (mk "<leader>fg" "require('mini.pick').builtin.grep_live()" "Live grep")
    (mk "<C-f>" "require('mini.pick').builtin.grep_live()" "Live grep")
    (mk "<leader>fh" "require('mini.pick').builtin.help()" "Help tags")
    (mk "<leader>fr" "require('mini.pick').builtin.resume()" "Resume last picker")
    (mk "<C-p>" "require('mini.extra').pickers.git_files()" "Git files")
    (mk "<leader>fo" "require('mini.extra').pickers.oldfiles()" "Recent files")
    (mk "<leader>fd" "require('mini.extra').pickers.diagnostic()" "Diagnostics")
    (mk "<leader>f/" "require('mini.extra').pickers.buf_lines({ scope = 'current' })" "Search in buffer")

    # Files changed on this branch since it diverged from its base (upstream
    # fork-point, not assumed to be origin/main). Includes uncommitted changes.
    (mk "<leader>fB" "_G.MiniPickGitChanged((_G.GitState.get_branch_point() or 'HEAD') .. '...HEAD', 'Branch changes')" "Branch changed files")

    # Every git hunk (searchable), diffed against the shared GitState base so it
    # matches the gutter signs / <leader>gd / <leader>gl.
    (mk "<leader>fH" "_G.MiniPickGitHunks()" "Git hunks (vs base)")

    # Prompt for a git rev/range and list its changed files, e.g. HEAD~4, main,
    # abc123..def456. Empty input defaults to HEAD~1.
    {
      mode = "n";
      key = "<leader>fD";
      action = lib.nixvim.mkRaw ''
        function()
          vim.ui.input({ prompt = "Git diff range: ", default = "HEAD~1" }, function(rev)
            if rev == nil or rev == "" then return end
            _G.MiniPickGitChanged(rev, "Diff " .. rev)
          end)
        end
      '';
      options = { silent = true; desc = "Diff range → changed files"; };
    }
    (mk "<leader>fc" "require('mini.extra').pickers.commands()" "Commands")
    (mk "<leader>fk" "require('mini.extra').pickers.keymaps()" "Keymaps")
    (mk "<leader>ls" "require('mini.extra').pickers.lsp({ scope = 'document_symbol' })" "Document symbols")
    (mk "<leader>lS" "require('mini.extra').pickers.lsp({ scope = 'workspace_symbol' })" "Workspace symbols")

    # Cheatsheet: query "dorking" sigils + in-picker actions. Shown in a small
    # scratch float so it's discoverable without leaving the editor.
    {
      mode = "n";
      key = "<leader>f?";
      action = lib.nixvim.mkRaw ''
        function()
          local lines = {
            "  mini.pick search cheatsheet",
            "",
            "  Query sigils (type in prompt):",
            "    foo      fuzzy (chars in order, gaps ok)",
            "    'foo     exact substring",
            "    ^foo     exact at start",
            "    foo$     exact at end",
            "    *foo     force fuzzy",
            "    a b      space = separate words (each matched)",
            "",
            "  In-picker actions:",
            "    <Tab>       toggle preview",
            "    <C-Space>   refine: freeze matches, filter again (stack!)",
            "    <C-u>       reset match to default (live grep)",
            "    <C-x>       mark/unmark  ->  choose-marked opens all",
            "    <C-j>/<C-k> move down / up",
            "",
            "  Live grep (<leader>fg): prompt goes to ripgrep, so",
            "  ripgrep regex works directly.",
          }
          local buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          vim.bo[buf].modifiable = false
          vim.bo[buf].bufhidden = "wipe"
          local width, height = 62, #lines + 1
          local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            width = width,
            height = height,
            row = math.floor((vim.o.lines - height) / 2),
            col = math.floor((vim.o.columns - width) / 2),
            style = "minimal",
            border = "rounded",
            title = " Picker help ",
          })
          vim.wo[win].cursorline = false
          vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true })
          vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, nowait = true })
        end
      '';
      options = { silent = true; desc = "Picker search help"; };
    }

    # Buffers picker with <C-d> to wipeout the buffer under the cursor.
    {
      mode = "n";
      key = "<leader>fb";
      action = lib.nixvim.mkRaw ''
        function()
          local MiniPick = require('mini.pick')
          MiniPick.builtin.buffers({}, {
            mappings = {
              wipeout = {
                char = "<C-d>",
                func = function()
                  local cur = MiniPick.get_picker_matches().current
                  if cur then
                    vim.api.nvim_buf_delete(cur.bufnr, {})
                  end
                end,
              },
            },
          })
        end
      '';
      options = {
        silent = true;
        desc = "Buffers";
      };
    }
  ];
}
