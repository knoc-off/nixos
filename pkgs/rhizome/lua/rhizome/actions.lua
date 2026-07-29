--- The `:Rhizome <verb>` action table.
---
--- One table backs two front-ends: `:Rhizome <Tab>` completion and the
--- `:Rhizome actions` picker. Keeping them as views over the same data is the
--- point -- a flat pile of `:RhizomeXxx` commands stops scaling once verbs
--- start taking arguments and needing per-argument completion.

local M = {}

--- Filled in by `setup()`, once `rhizome` itself has finished loading. Doing
--- this lazily (rather than `require`d at file scope) avoids a load-order
--- dependency: `actions.lua` is only required from inside `rhizome.setup()`,
--- by which point `rhizome`'s own module table is complete.
local rhizome

--- Current note id for actions that need one, or nil with a notification
--- already issued.
local function note_id()
  local bufnr = vim.api.nvim_get_current_buf()
  local tracked = rhizome._buffer(bufnr)
  if not tracked then
    vim.notify("rhizome: not a Trilium buffer", vim.log.levels.ERROR)
    return nil
  end
  return tracked.note_id
end

---@type table<string, { desc: string, takes_args?: boolean, run: fun(args: string, mods: table), complete?: fun(lead: string): string[] }>
M.actions = {
  pick = {
    desc = "Pick a note",
    run = function(_, mods)
      rhizome.pick("", mods)
    end,
  },
  search = {
    desc = "Search notes by query",
    takes_args = true,
    run = function(args, mods)
      rhizome.pick(args, mods)
    end,
  },
  browse = {
    desc = "Browse notes by hierarchy (or '.'/'..'/a noteId to start elsewhere)",
    takes_args = true,
    run = function(args, mods)
      args = vim.trim(args or "")
      if args == "" then
        rhizome.browse({}, mods)
      elseif args == "." or args == ".." then
        local id = note_id()
        if not id then
          return
        end
        if args == "." then
          rhizome.browse_at(id, mods)
        else
          rhizome.browse_up(id, mods)
        end
      else
        rhizome.browse_at(args, mods)
      end
    end,
  },
  open = {
    desc = "Open a note by id",
    takes_args = true,
    run = function(args, mods)
      if args == "" then
        rhizome.pick("")
        return
      end
      rhizome.open(args, { mods = mods })
    end,
  },
  meta = {
    desc = "Edit this note's title, labels and relations",
    run = function()
      rhizome.metadata()
    end,
  },
  rename = {
    desc = "Rename this note",
    takes_args = true,
    run = function(args)
      if args == "" then
        vim.notify("rhizome: rename needs a title", vim.log.levels.ERROR)
        return
      end
      rhizome.rename(args)
    end,
  },
  actions = {
    desc = "Browse and run rhizome actions",
    run = function()
      M.picker()
    end,
  },
  today = {
    desc = "Open (or create) today's day note",
    run = function(_, mods)
      rhizome.open_date_note("today", mods)
    end,
  },
  yesterday = {
    desc = "Open (or create) yesterday's day note",
    run = function(_, mods)
      rhizome.open_date_note("yesterday", mods)
    end,
  },
  tomorrow = {
    desc = "Open (or create) tomorrow's day note",
    run = function(_, mods)
      rhizome.open_date_note("tomorrow", mods)
    end,
  },
  date = {
    desc = "Open (or create) the day note for a YYYY-MM-DD date",
    takes_args = true,
    run = function(args, mods)
      if args == "" then
        vim.notify("rhizome: date needs a YYYY-MM-DD argument", vim.log.levels.ERROR)
        return
      end
      rhizome.open_date_note(args, mods)
    end,
  },
  inbox = {
    desc = "Open (or create) today's inbox note",
    run = function(_, mods)
      rhizome.open_inbox(mods)
    end,
  },
  new = {
    desc = "Create a note under today's inbox",
    takes_args = true,
    run = function(args, mods)
      rhizome.create_note(args, nil, mods)
    end,
  },
  child = {
    desc = "Create a note under the current note",
    takes_args = true,
    run = function(args, mods)
      local id = note_id()
      if not id then
        return
      end
      rhizome.create_note(args, id, mods)
    end,
  },
  move = {
    desc = "Move this note to a different parent",
    run = function()
      local id = note_id()
      if id then
        rhizome.move_note(id)
      end
    end,
  },
  clone = {
    desc = "Clone this note to a different parent",
    run = function()
      local id = note_id()
      if id then
        rhizome.clone_note(id)
      end
    end,
  },
  unlink = {
    desc = "Remove this note from one of its parents",
    run = function()
      local id = note_id()
      if id then
        rhizome.unlink_note(id)
      end
    end,
  },
  delete = {
    desc = "Delete this note everywhere",
    run = function()
      local id = note_id()
      if id then
        rhizome.delete_note(id)
      end
    end,
  },
  archive = {
    desc = "Archive this note",
    run = function()
      local id = note_id()
      if id then
        rhizome.archive_note(id)
      end
    end,
  },
  unarchive = {
    desc = "Unarchive this note",
    run = function()
      local id = note_id()
      if id then
        rhizome.unarchive_note(id)
      end
    end,
  },
  link = {
    desc = "Search and insert a link at the cursor",
    takes_args = true,
    run = function(args)
      rhizome.insert_link(args)
    end,
  },
  notes = {
    desc = "Browse every note by title or path and insert a link",
    run = function()
      rhizome.insert_link_from_index()
    end,
  },
  reindex = {
    desc = "Refresh the local note index used by 'notes' and path search",
    run = function()
      rhizome.reindex()
    end,
  },
}

--- Dispatch `:Rhizome <name> <rest>`. `mods` carries the command modifiers
--- (`:vertical`, `:tab`, ...) so verbs that open a buffer can honor them.
function M.dispatch(fargs, mods)
  local name = fargs[1]
  if not name or name == "" then
    M.actions.pick.run("", mods)
    return
  end
  local action = M.actions[name]
  if not action then
    local names = vim.tbl_keys(M.actions)
    table.sort(names)
    vim.notify(
      ("rhizome: no action '%s'. Try: %s"):format(name, table.concat(names, ", ")),
      vim.log.levels.ERROR
    )
    return
  end
  local rest = table.concat(fargs, " ", 2, #fargs)
  action.run(rest, mods)
end

--- Completion for `:Rhizome <Tab>`.
function M.complete(arg_lead, cmd_line)
  local before_cursor = cmd_line:match("^%S+%s+(.*)$") or ""
  local first_space = before_cursor:find("%s")
  if not first_space then
    local names = vim.tbl_keys(M.actions)
    table.sort(names)
    return vim.tbl_filter(function(n)
      return n:sub(1, #arg_lead) == arg_lead
    end, names)
  end
  local verb = before_cursor:sub(1, first_space - 1)
  local action = M.actions[verb]
  if action and action.complete then
    local ok, items = pcall(action.complete)
    if ok and items then
      return vim.tbl_filter(function(item)
        return item:sub(1, #arg_lead) == arg_lead
      end, items)
    end
  end
  return {}
end

--- `:Rhizome actions` -- the same table, browsable.
function M.picker()
  local names = vim.tbl_keys(M.actions)
  table.sort(names)
  local items = {}
  for _, name in ipairs(names) do
    table.insert(items, { text = ("%-12s %s"):format(name, M.actions[name].desc), name = name })
  end

  local function choose(item)
    local action = M.actions[item.name]
    if action.takes_args then
      -- Needs an argument: hand it to the cmdline rather than guessing.
      vim.schedule(function()
        vim.fn.feedkeys((":Rhizome %s "):format(item.name), "n")
      end)
      return
    end
    vim.schedule(function()
      action.run("", {})
    end)
  end

  local ok, pick = pcall(require, "mini.pick")
  if ok then
    pick.start({
      source = { items = items, name = "rhizome actions", choose = choose },
    })
  else
    vim.ui.select(items, {
      prompt = "rhizome actions",
      format_item = function(item)
        return item.text
      end,
    }, function(item)
      if item then
        choose(item)
      end
    end)
  end
end

function M.setup(rhizome_module)
  rhizome = rhizome_module
end

return M
