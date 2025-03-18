{
  plugins.which-key = {
    enable = true;
    settings = {
      plugins = {
        registers = true;
        spelling = {
          enabled = true;
          suggestions = 20;
        };
        presets = {
          operators = true;
          motions = true;
          text_objects = true;
          windows = true;
          nav = true;
          z = true;
          g = true;
        };
      };
      # operators = { gc = "Comments"; };
      key_labels = {
        "<space>" = "SPC";
        "<cr>" = "RET";
        "<tab>" = "TAB";
      };
      motions = { count = true; };
      icons = {
        breadcrumb = "»";
        separator = "➜";
        group = "+";
      };
      popup_mappings = {
        scrollDown = "<c-d>";
        scrollUp = "<c-u>";
      };
      layout = {
        height = { min = 4; max = 25; };
        width = { min = 20; max = 50; };
        spacing = 3;
        align = "left";
      };
      win = {
        border = "single";
        # padding takes a list of [vertical horizontal] integers
        padding = [ 1 2 ];
        winblend = 0;
        title_pos = "bottom";
        footer_pos = "bottom";
      };
      ignore_missing = false;
      show_help = true;
      show_keys = true;
      # Specify triggers as a list with an attribute set containing __raw.
      # This tells nix that the value is raw Lua code.
      triggers = [ { __raw = "auto"; } ];
      triggers_nowait = [ "`" "'" "g`" "g'" "<c-r>" "z=" ];
      triggers_blacklist = {
        i = [ "j" "k" ];
        v = [ "j" "k" ];
      };
      disable = {
        ft = [ ]; # filetypes
        bt = [ ]; # buftypes
      };
    };
  };
}

