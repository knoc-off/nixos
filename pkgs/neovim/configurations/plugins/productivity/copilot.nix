{ pkgs, ... }:
{
  plugins = {
    copilot-lua = {
      enable = true;
      autoLoad = true;
      settings = {
        autostart = true;
        event = [
          "InsertEnter"
          "LspAttach"
        ];
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
          show_info = { normal = "gp"; };
        };
      };
    };
  };
}
