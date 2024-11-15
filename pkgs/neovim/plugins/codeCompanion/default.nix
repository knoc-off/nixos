{ lib, ... }:
# lib.x86_64-linux.helpers.neovim-plugin.mkNeovimPlugin
{
  name = "codecompanion";
  #maintainers = [ maintainers.YourName ];
  settingsOptions = {
    strategies = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {
        chat = {
          adapter = "copilot";
          opts = {
            register = "+";
            model = "claude-3-sonnet";
          };
        };
        inline = {
          adapter = "copilot";
        };
      };
      description = "Configuration for strategies";
    };
    display = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {
        chat = {
          window = {
            layout = "vertical";
            width = 0.45;
            height = 0.8;
          };
          start_in_insert_mode = false;
        };
        diff = {
          enabled = true;
          layout = "vertical";
        };
      };
      description = "Configuration for display";
    };
    opts = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = {
        log_level = "ERROR";
        send_code = true;
      };
      description = "General options";
    };
  };
  extraConfigLua = ''
    require("codecompanion").setup({
      strategies = {
        chat = {
          adapter = "copilot";
          opts = {
            register = "+";
            model = "claude-3-sonnet";
          };
        };
        inline = {
          adapter = "copilot";
        };
      };
      display = {
        chat = {
          window = {
            layout = "vertical";
            width = 0.45;
            height = 0.8;
          };
          start_in_insert_mode = false;
        };
        diff = {
          enabled = true;
          layout = "vertical";
        };
      };
      opts = {
        log_level = "ERROR";
        send_code = true;
      };
    })
  '';
}
