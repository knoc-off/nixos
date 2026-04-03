# Custom fold display: joins all lines with treesitter highlights, truncates at window edge
{
  extraConfigLuaPre = ''
    local fold_cache = {}

    local function get_text_width()
      local win = vim.api.nvim_get_current_win()
      local info = vim.fn.getwininfo(win)[1]
      return vim.api.nvim_win_get_width(win) - (info.textoff or 0)
    end

    local function append_highlighted(result, text, lnum_0, col_offset, budget)
      local consumed = 0
      local chunk = ""
      local hl = nil

      for i = 1, #text do
        if consumed >= budget then break end
        local char = text:sub(i, i)
        local new_hl = nil
        local captures = vim.treesitter.get_captures_at_pos(0, lnum_0, col_offset + i - 1)
        if #captures > 0 then
          local cap = captures[#captures]
          new_hl = "@" .. cap.capture
          if cap.lang then
            new_hl = new_hl .. "." .. cap.lang
          end
        end

        if new_hl ~= hl then
          if #chunk > 0 then
            table.insert(result, { chunk, hl })
          end
          chunk = char
          hl = new_hl
        else
          chunk = chunk .. char
        end
        consumed = consumed + 1
      end

      if #chunk > 0 then
        table.insert(result, { chunk, hl })
      end
      return consumed
    end

    local function compute_foldtext(text_width)
      local result = {}
      local fold_lines = vim.v.foldend - vim.v.foldstart + 1
      local tab_expand = string.rep(" ", vim.o.tabstop)

      -- Pre-scan: collect line data and total display width
      local lines_data = {}
      local total_needed = 0
      for lnum = vim.v.foldstart, vim.v.foldend do
        local raw = vim.fn.getline(lnum)
        if lnum == vim.v.foldstart then
          local expanded = raw:gsub("\t", tab_expand)
          table.insert(lines_data, { text = expanded, lnum_0 = lnum - 1, offset = 0 })
          total_needed = total_needed + #expanded
        else
          local trimmed = vim.trim(raw)
          if #trimmed > 0 then
            local leading = #(raw:match("^(%s+)") or "")
            table.insert(lines_data, { text = trimmed, lnum_0 = lnum - 1, offset = leading })
            total_needed = total_needed + 1 + #trimmed
          end
        end
      end

      -- Only show suffix when content is actually truncated
      local suffix = " ..." .. fold_lines
      local truncated = total_needed > text_width
      local budget = truncated and math.max(0, text_width - #suffix) or text_width
      local consumed = 0

      for idx, data in ipairs(lines_data) do
        if consumed >= budget then break end

        -- Space separator between lines (not before first)
        if idx > 1 then
          table.insert(result, { " ", nil })
          consumed = consumed + 1
          if consumed >= budget then break end
        end

        consumed = consumed + append_highlighted(
          result, data.text, data.lnum_0, data.offset, budget - consumed
        )
      end

      if truncated then
        table.insert(result, { suffix, "Comment" })
      end

      return result
    end

    function _G.custom_foldtext()
      local bufnr = vim.api.nvim_get_current_buf()
      local tick = vim.api.nvim_buf_get_changedtick(bufnr)
      local width = get_text_width()

      -- Invalidate cache if buffer changed or window resized
      local bc = fold_cache[bufnr]
      if not bc or bc.tick ~= tick or bc.width ~= width then
        fold_cache[bufnr] = { tick = tick, width = width, folds = {} }
        bc = fold_cache[bufnr]
      end

      local key = vim.v.foldstart
      if bc.folds[key] then
        return bc.folds[key]
      end

      local result = compute_foldtext(width)
      bc.folds[key] = result
      return result
    end

    vim.opt.foldtext = "v:lua.custom_foldtext()"
    vim.opt.fillchars:append({ fold = " " })

    -- Clean up cache when buffers are removed
    vim.api.nvim_create_autocmd("BufWipeout", {
      callback = function(ev)
        fold_cache[ev.buf] = nil
      end,
    })
  '';
}
