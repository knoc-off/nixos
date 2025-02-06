{ pkgs, ... }:
let
  o1 = pkgs.writeTextFile {
    name = "o1.lua";
    text = ''
      local M = {}

      function M.get_adapter()
        local adapters = require('codecompanion.adapters')

        -- Extend the Copilot adapter with specific parameters and handlers for o1 models
        local adapter = adapters.extend('copilot', {
          schema = {
            model = {
              order = 1,
              mapping = "parameters",
              type = "enum",
              desc = "ID of the model to use. See the model endpoint compatibility table for details on which models work with the Chat API.",
              default = "gpt-4o-2024-08-06",
              choices = {
                "gpt-4o-2024-08-06",
                "claude-3.5-sonnet",
                ["o1-preview-2024-09-12"] = { opts = { stream = false } },
                ["o1-mini-2024-09-12"] = { opts = { stream = false } },
              },
            },
          },
        })
        adapter.name = 'copilot_o1'
        return adapter
      end

      return M
    '';
  };
in
{
  extraPlugins = [ pkgs.vimExtraPlugins.codecompanion-nvim ];

  extraConfigLua = ''
    -- Load the o1.lua module
    local o1 = dofile("${o1}")

    require("codecompanion").setup({
      adapters = {
        copilot_o1 = o1.get_adapter(),
      },
      strategies = {
        chat = {
          adapter = "copilot_o1", -- Use the custom adapter
          opts = {
            register = "+"
          },
        },
        inline = {
          adapter = "copilot"
        }
      },
      display = {
        chat = {
          window = {
            layout = "vertical",
            width = 0.1,
            height = 0.4
          },
          start_in_insert_mode = false
        },
        diff = {
          enabled = true,
          layout = "vertical"
        }
      },
      opts = {
        log_level = "ERROR",
        send_code = true
      }
    })
  '';
}
