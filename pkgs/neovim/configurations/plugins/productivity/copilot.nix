{ pkgs, ... }: {

  extraPlugins =  [ pkgs.vimExtraPlugins.codecompanion-nvim ];



  # Then add the configuration
  extraConfigLua = ''
    require("codecompanion").setup({
      strategies = {
        chat = {
          adapter = "anthropic", -- Switch between: anthropic|copilot|gemini|openai
          opts = {
            register = "+" -- Register to use for yanking code
          },
        },
        inline = {
          adapter = "copilot" -- Default adapter for inline completions
        }
      },
      display = {
        chat = {
          window = {
            layout = "vertical", -- float|vertical|horizontal|buffer
            width = 0.45,
            height = 0.8
          },
          start_in_insert_mode = false
        },
        diff = {
          enabled = true,
          layout = "vertical" -- vertical|horizontal
        }
      },
      opts = {
        log_level = "ERROR", -- TRACE|DEBUG|ERROR|INFO
        send_code = true -- Whether to allow sending code to LLMs
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

    #copilot-chat = {
    #  enable = true;
    #  settings = {
    #    debug = false;
    #    model = "gpt-4";
    #    temperature = 0.1;
    #    show_help = true;
    #    auto_follow_cursor = true;
    #    clear_chat_on_new_prompt = false;
    #    context = "buffer";
    #    prompts = { };
    #    window = {
    #      layout = "vertical";
    #      width = 0.4;
    #      border = "single";
    #    };
    #    mappings = {
    #      close = {
    #        normal = "q";
    #        insert = "<C-c>";
    #      };
    #      reset = {
    #        normal = "<C-l>";
    #        insert = "<C-l>";
    #      };
    #      submit_prompt = {
    #        normal = "<CR>";
    #        insert = "<C-CR>";
    #      };
    #      accept_diff = {
    #        normal = "<C-y>";
    #        insert = "<C-y>";
    #      };
    #      show_diff = { normal = "gd"; };
    #      show_system_prompt = { normal = "gp"; };
    #    };
    #  };
    #};
  };
}
