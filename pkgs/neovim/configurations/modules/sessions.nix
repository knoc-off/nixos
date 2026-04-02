# Session management via mini.sessions
# Slots 1-3 for quick save/load, plus named sessions with picker
{lib, ...}: let
  saveSlotKeymaps = builtins.genList (i: let
    n = toString (i + 1);
  in {
    mode = "n";
    key = "<leader>s${n}";
    action = lib.nixvim.mkRaw ''
      function()
        require('mini.sessions').write("slot_${n}")
        vim.notify("Session saved to slot ${n}", vim.log.levels.INFO)
      end
    '';
    options = { silent = true; desc = "Save session slot ${n}"; };
  }) 3;

  loadSlotKeymaps = builtins.genList (i: let
    n = toString (i + 1);
  in {
    mode = "n";
    key = "<leader>S${n}";
    action = lib.nixvim.mkRaw ''
      function()
        local MiniSessions = require('mini.sessions')
        if MiniSessions.detected["slot_${n}"] then
          MiniSessions.read("slot_${n}")
          vim.notify("Session loaded from slot ${n}", vim.log.levels.INFO)
        else
          vim.notify("No session in slot ${n}", vim.log.levels.WARN)
        end
      end
    '';
    options = { silent = true; desc = "Load session slot ${n}"; };
  }) 3;
in {
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

  keymaps =
    [
      {
        mode = "n";
        key = "<leader>ss";
        action = lib.nixvim.mkRaw ''
          function()
            vim.ui.input({ prompt = "Session name: " }, function(name)
              if name and name ~= "" then
                require('mini.sessions').write(name)
                vim.notify("Session saved: " .. name, vim.log.levels.INFO)
              end
            end)
          end
        '';
        options = { silent = true; desc = "Save session (named)"; };
      }
      {
        mode = "n";
        key = "<leader>sl";
        action = lib.nixvim.mkRaw ''
          function()
            local MiniSessions = require('mini.sessions')
            local sessions = vim.tbl_keys(MiniSessions.detected)
            if #sessions == 0 then
              vim.notify("No sessions found", vim.log.levels.WARN)
              return
            end
            table.sort(sessions)
            vim.ui.select(sessions, { prompt = "Load session:" }, function(choice)
              if choice then MiniSessions.read(choice) end
            end)
          end
        '';
        options = { silent = true; desc = "Load session (pick)"; };
      }
      {
        mode = "n";
        key = "<leader>sd";
        action = lib.nixvim.mkRaw ''
          function()
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
        options = { silent = true; desc = "Delete session"; };
      }
    ]
    ++ saveSlotKeymaps
    ++ loadSlotKeymaps;
}
