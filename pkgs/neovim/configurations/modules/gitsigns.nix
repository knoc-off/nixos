{lib, ...}: {
  #plugins gitsigns
  plugins.gitsigns = {
    enable = true;
    settings = {
      diff_opts = {
        vertical = true;
      };
    };
  };

  # Initialize gitsigns base state tracking
  extraConfigLuaPre = ''
    -- Track gitsigns base state: 'HEAD' or 'merge-base'
    _G.gitsigns_base_state = 'HEAD'
    _G.gitsigns_base_description = 'HEAD'

    -- Interactive gitsigns base picker - hierarchical menu
    _G.gitsigns_base_picker = function()
      local gs = require('gitsigns')
      local pickers = require('telescope.pickers')
      local finders = require('telescope.finders')
      local conf = require('telescope.config').values
      local actions = require('telescope.actions')
      local action_state = require('telescope.actions.state')

      -- Second level pickers for each category
      local function pick_commit()
        local commits = vim.fn.systemlist('git log --oneline --decorate -100')
        local commit_entries = {}
        for i, commit in ipairs(commits) do
          local hash = commit:match('^(%S+)')
          local message = commit:match('^%S+%s+(.*)$') or '''
          local head_index = i - 1
          table.insert(commit_entries, {
            display = string.format('[HEAD~%d] %s', head_index, commit),
            value = hash,
            description = 'HEAD~' .. head_index,
            ordinal = string.format('%03d %s', head_index, commit)
          })
        end

        pickers.new({}, {
          prompt_title = 'Select Commit (sorted by recency)',
          finder = finders.new_table({
            results = commit_entries,
            entry_maker = function(entry)
              return {
                value = entry,
                display = entry.display,
                ordinal = entry.ordinal,
              }
            end,
          }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              local entry = selection.value
              gs.change_base(entry.value, true)
              _G.gitsigns_base_state = entry.value
              _G.gitsigns_base_description = entry.description
              vim.notify('Gitsigns base set to ' .. entry.description, vim.log.levels.INFO)
            end)
            return true
          end,
        }):find()
      end

      local function pick_merge_base()
        local branches = vim.fn.systemlist('git branch -a | sed "s/^[* ]*//" | sed "s/^remotes\\\\///"')
        local branch_entries = {}
        for _, branch in ipairs(branches) do
          if branch ~= ''' and not branch:match('HEAD') then
            table.insert(branch_entries, { display = branch, value = branch })
          end
        end

        pickers.new({}, {
          prompt_title = 'Select Branch for Merge-Base',
          finder = finders.new_table({
            results = branch_entries,
            entry_maker = function(entry)
              return {
                value = entry,
                display = entry.display,
                ordinal = entry.display,
              }
            end,
          }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              local entry = selection.value
              local merge_base = vim.fn.system('git merge-base HEAD ' .. entry.value .. ' 2>/dev/null'):gsub('\n', ''')
              if vim.v.shell_error == 0 and merge_base ~= "" then
                gs.change_base(merge_base, true)
                _G.gitsigns_base_state = merge_base
                _G.gitsigns_base_description = 'merge-base(' .. entry.value .. ')'
                vim.notify('Gitsigns base set to merge-base with ' .. entry.value .. ' (' .. merge_base:sub(1,8) .. ')', vim.log.levels.INFO)
              else
                vim.notify('Failed to get merge-base with ' .. entry.value, vim.log.levels.ERROR)
              end
            end)
            return true
          end,
        }):find()
      end

      local function pick_tag()
        local tags = vim.fn.systemlist('git tag --sort=-creatordate')
        if #tags == 0 then
          vim.notify('No tags found in repository', vim.log.levels.WARN)
          return
        end

        local tag_entries = {}
        for _, tag in ipairs(tags) do
          if tag ~= ''' then
            table.insert(tag_entries, { display = tag, value = tag })
          end
        end

        pickers.new({}, {
          prompt_title = 'Select Tag',
          finder = finders.new_table({
            results = tag_entries,
            entry_maker = function(entry)
              return {
                value = entry,
                display = entry.display,
                ordinal = entry.display,
              }
            end,
          }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              local selection = action_state.get_selected_entry()
              actions.close(prompt_bufnr)
              local entry = selection.value
              gs.change_base(entry.value, true)
              _G.gitsigns_base_state = entry.value
              _G.gitsigns_base_description = 'tag(' .. entry.value .. ')'
              vim.notify('Gitsigns base set to tag ' .. entry.value, vim.log.levels.INFO)
            end)
            return true
          end,
        }):find()
      end

      -- Main category picker
      local categories = {
        { display = '󰜘 HEAD (reset to current)', action = function()
          gs.change_base(nil, true)
          _G.gitsigns_base_state = 'HEAD'
          _G.gitsigns_base_description = 'HEAD'
          vim.notify('Gitsigns base reset to HEAD', vim.log.levels.INFO)
        end },
        { display = ' Commits (browse all commits)', action = pick_commit },
        { display = ' Merge-base (with branch)', action = pick_merge_base },
        { display = ' Tags', action = pick_tag },
      }

      pickers.new({}, {
        prompt_title = 'Select Gitsigns Diff Base Category',
        finder = finders.new_table({
          results = categories,
          entry_maker = function(entry)
            return {
              value = entry,
              display = entry.display,
              ordinal = entry.display,
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            actions.close(prompt_bufnr)
            selection.value.action()
          end)
          return true
        end,
      }):find()
    end
  '';

  keymaps = [
    {
      mode = "n";
      key = "<leader>gB";
      action = lib.nixvim.mkRaw "_G.gitsigns_base_picker";
      options = {
        silent = true;
        desc = "Pick gitsigns diff base";
      };
    }
    {
      mode = "n";
      key = "<leader>gm";
      action = lib.nixvim.mkRaw ''
        function()
          local gs = require('gitsigns')

          if _G.gitsigns_base_state == 'HEAD' then
            -- Switch to merge-base
            local merge_base = vim.fn.system('git merge-base HEAD origin/main'):gsub('\n', ''')

            if vim.v.shell_error == 0 and merge_base ~= "" then
              gs.change_base(merge_base, true)
              _G.gitsigns_base_state = 'merge-base'
              _G.gitsigns_base_description = 'merge-base(origin/main)'
              vim.notify('Gitsigns base set to merge-base with origin/main (' .. merge_base:sub(1,8) .. ')', vim.log.levels.INFO)
            else
              vim.notify('Failed to get merge-base with origin/main. Are you in a git repo with origin/main?', vim.log.levels.WARN)
            end
          else
            -- Switch back to HEAD
            gs.change_base(nil, true)
            _G.gitsigns_base_state = 'HEAD'
            _G.gitsigns_base_description = 'HEAD'
            vim.notify('Gitsigns base reset to HEAD', vim.log.levels.INFO)
          end
        end
      '';
      options = {
        silent = true;
        desc = "Toggle Gitsigns base (HEAD ↔ merge-base with origin/main)";
      };
    }
  ];
}
