# Avante.nvim - AI agent UI via ACP (Agent Client Protocol)
# Uses OpenCode as the backend agent -- all tools, MCP servers, rules, and
# permissions are handled by OpenCode. Avante is just the neovim UI layer.
{lib, ...}: {
  plugins.avante = {
    enable = true;

    settings = {
      provider = "opencode";
      mode = "agentic";

      acp_providers = {
        opencode = {
          command = "opencode";
          args = ["acp"];
        };
      };

      behaviour = {
        auto_suggestions = false; # no inline ghost text
        auto_set_keymaps = false; # we define our own below
        auto_set_highlight_group = true;
        auto_apply_diff_after_generation = false; # review before applying
        minimize_diff = true;
        auto_add_current_file = true;
      };

      hints.enabled = false; # no virtual text hints cluttering the buffer

      windows = {
        position = "right";
        wrap = true;
        width = 30;
        sidebar_header = {
          align = "center";
          rounded = true;
        };
        edit = {
          border = "rounded";
          start_insert = false;
        };
        ask.start_insert = false;
      };

      mappings = {
        edit = "<leader>ae";
        refresh = "<leader>ar";
        diff = {
          ours = "co";
          theirs = "ct";
          both = "cb";
          all_theirs = "ca";
          cursor = "cc";
          next = "]x";
          prev = "[x";
        };
        jump = {
          next = "]]";
          prev = "[[";
        };
        submit = {
          normal = "<CR>";
          insert = "<C-s>";
        };
        toggle = {
          default = "<leader>at";
          debug = "<leader>ad";
          hint = "<leader>ah";
        };
      };
    };
  };

  keymaps = [
    {
      mode = ["n" "v"];
      key = "<leader>aa";
      action = lib.nixvim.mkRaw ''
        function()
          local mode = vim.fn.mode()
          if mode == 'n' then
            local avante = require('avante')
            if avante.is_sidebar_open() then
              avante.close_sidebar()
              return
            end
          end
          require('avante.api').ask({ new_chat = true })
        end
      '';
      options = {
        desc = "Avante: ask / toggle";
        silent = true;
      };
    }
    {
      mode = "v";
      key = "<leader>ae";
      action = lib.nixvim.mkRaw "function() require('avante.api').edit() end";
      options = {
        desc = "Avante: edit selection";
        silent = true;
      };
    }
    {
      mode = "n";
      key = "<leader>ar";
      action = lib.nixvim.mkRaw "function() require('avante.api').refresh() end";
      options = {
        desc = "Avante: refresh";
        silent = true;
      };
    }
    {
      mode = "n";
      key = "<leader>at";
      action = lib.nixvim.mkRaw "function() require('avante').toggle() end";
      options = {
        desc = "Avante: toggle panel";
        silent = true;
      };
    }
  ];
}
