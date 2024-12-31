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
          opts = { stream = false }, -- Stream not supported
          schema = {
            model = {
              default = 'o1',
              choices = {
                'o1',
                'o1-mini',
              },
            },
          },
          handlers = {
            ---Handler to remove system prompt from messages
            ---@param self CodeCompanion.Adapter
            ---@param messages table
            form_messages = function(self, messages)
              return {
                messages = vim
                  .iter(messages)
                  :filter(function(message) return not (message.role and message.role == 'system') end)
                  :totable(),
              }
            end,
          },
        })

        -- Remove unsupported settings from the adapter schema
        local unsupported_settings = { 'temperature', 'max_tokens', 'top_p', 'n' }
        vim.iter(unsupported_settings):each(function(setting) adapter.schema[setting] = nil end)

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

  plugins = {
    copilot-lua = {
      enable = true;
      filetypes = {
        "*" = true;
        markdown = false;
        yaml = false;
        json = false;
        toml = false;
        ini = false;
        passwd = false;
        netrc = false;
        gpg = false;
        asc = false;
      };
      suggestion = {
        enabled = true;
        autoTrigger = true;
      };
      panel = { enabled = true; };
    };

    copilot-chat = {
      enable = true;
      settings = {
        debug = false;
        model = "gpt-4";
        temperature = 0.1;
        show_help = true;
        auto_follow_cursor = true;
        clear_chat_on_new_prompt = false;
        context = "buffer";
        prompts = { };
        window = {
          layout = "vertical";
          width = 0.4;
          border = "single";
        };
        mappings = {
          close = {
            normal = "q";
            insert = "<C-c>";
          };
          reset = {
            normal = "<C-l>";
            insert = "<C-l>";
          };
          submit_prompt = {
            normal = "<CR>";
            insert = "<C-CR>";
          };
          accept_diff = {
            normal = "<C-y>";
            insert = "<C-y>";
          };
          show_diff = { normal = "gd"; };
          show_system_prompt = { normal = "gp"; };
        };
      };
    };
  };
}
