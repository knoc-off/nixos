# Session management via mini.sessions
# Marks-like slots (m1/m2/m3 to save, '1/'2/'3 to load) + named sessions
{lib, ...}: {
  plugins.mini.enable = true;
  plugins.mini.mockDevIcons = true;
  plugins.mini.modules.icons = {};
  plugins.mini-sessions = {
    enable = true;
    settings = {
      autoread = false;
      autowrite = false;
      directory = lib.nixvim.mkRaw "vim.fn.stdpath('data') .. '/sessions'";
      file = "";
      force = {
        read = false;
        write = true;
        delete = false;
      };
      verbose = {
        read = true;
        write = true;
        delete = true;
      };
    };
  };

  extraConfigLuaPre = ''
    _G.save_session_slot = function(slot)
      local MiniSessions = require('mini.sessions')
      local name = "slot_" .. slot
      MiniSessions.write(name)
      vim.notify("Session saved to slot " .. slot, vim.log.levels.INFO)
    end

    _G.load_session_slot = function(slot)
      local MiniSessions = require('mini.sessions')
      local name = "slot_" .. slot
      if MiniSessions.detected[name] then
        MiniSessions.read(name)
        vim.notify("Session loaded from slot " .. slot, vim.log.levels.INFO)
      else
        vim.notify("No session in slot " .. slot, vim.log.levels.WARN)
      end
    end

    _G.save_session_named = function()
      vim.ui.input({ prompt = "Session name: " }, function(name)
        if name and name ~= "" then
          require('mini.sessions').write(name)
          vim.notify("Session saved: " .. name, vim.log.levels.INFO)
        end
      end)
    end

    _G.load_session_picker = function()
      local MiniSessions = require('mini.sessions')
      local sessions = vim.tbl_keys(MiniSessions.detected)
      if #sessions == 0 then
        vim.notify("No sessions found", vim.log.levels.WARN)
        return
      end
      table.sort(sessions)
      vim.ui.select(sessions, { prompt = "Load session:" }, function(choice)
        if choice then
          MiniSessions.read(choice)
        end
      end)
    end

    _G.delete_session_picker = function()
      local MiniSessions = require('mini.sessions')
      local sessions = vim.tbl_keys(MiniSessions.detected)
      if #sessions == 0 then
        vim.notify("No sessions found", vim.log.levels.WARN)
        return
      end
      table.sort(sessions)
      vim.ui.select(sessions, { prompt = "Delete session:" }, function(choice)
        if choice then
          MiniSessions.delete(choice)
          vim.notify("Session deleted: " .. choice, vim.log.levels.INFO)
        end
      end)
    end
  '';

  keymaps = [
    # Save: <leader>s + slot or 's' for named
    {
      mode = "n";
      key = "<leader>ss";
      action = lib.nixvim.mkRaw "_G.save_session_named";
      options = {
        silent = true;
        desc = "Save session (named)";
      };
    }
    {
      mode = "n";
      key = "<leader>s1";
      action = lib.nixvim.mkRaw "function() _G.save_session_slot(1) end";
      options = {
        silent = true;
        desc = "Save session slot 1";
      };
    }
    {
      mode = "n";
      key = "<leader>s2";
      action = lib.nixvim.mkRaw "function() _G.save_session_slot(2) end";
      options = {
        silent = true;
        desc = "Save session slot 2";
      };
    }
    {
      mode = "n";
      key = "<leader>s3";
      action = lib.nixvim.mkRaw "function() _G.save_session_slot(3) end";
      options = {
        silent = true;
        desc = "Save session slot 3";
      };
    }
    # Load: <leader>S + slot, or 'l' to pick
    {
      mode = "n";
      key = "<leader>sl";
      action = lib.nixvim.mkRaw "_G.load_session_picker";
      options = {
        silent = true;
        desc = "Load session (pick)";
      };
    }
    {
      mode = "n";
      key = "<leader>S1";
      action = lib.nixvim.mkRaw "function() _G.load_session_slot(1) end";
      options = {
        silent = true;
        desc = "Load session slot 1";
      };
    }
    {
      mode = "n";
      key = "<leader>S2";
      action = lib.nixvim.mkRaw "function() _G.load_session_slot(2) end";
      options = {
        silent = true;
        desc = "Load session slot 2";
      };
    }
    {
      mode = "n";
      key = "<leader>S3";
      action = lib.nixvim.mkRaw "function() _G.load_session_slot(3) end";
      options = {
        silent = true;
        desc = "Load session slot 3";
      };
    }
    # Delete
    {
      mode = "n";
      key = "<leader>sd";
      action = lib.nixvim.mkRaw "_G.delete_session_picker";
      options = {
        silent = true;
        desc = "Delete session";
      };
    }
  ];
}
