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
          operators   = true;
          motions     = true;
          text_objects = true;
          windows     = true;
          nav         = true;
          z           = true;
          g           = true;
        };
      };
      # operators = { gc = "Comments"; };  # remains commented out

      replace = {
        "<space>" = "SPC";
        "<cr>"    = "RET";
        "<tab>"   = "TAB";
      };

      icons = {
        breadcrumb = "»";
        separator  = "➜";
        group      = "+";
      };

      keys = {
        scrollDown = "<c-d>";
        scrollUp   = "<c-u>";
      };

      layout = {
        height  = { min = 4; max = 25; };
        width   = { min = 20; max = 50; };
        spacing = 3;
        align   = "left";
      };

      win = {
        border    = "single";
        # padding takes a list of [vertical horizontal] integers
        padding   = [ 1 2 ];
        winblend  = 0;
        title_pos = "bottom";
        footer_pos= "bottom";
      };

      # Replacing ignore_missing, which expected a boolean,
      # with filter. However, the new type is either null or a Lua
      # function string. Setting it to null turns off filtering.
      filter = null;

      show_help = true;
      show_keys = true;

      triggers = {
        __raw = "auto";
        blacklist = {
          i = [ "j" "k" ];
          v = [ "j" "k" ];
        };
      };

      # Instead of triggers_nowait, we now use a numerical delay.
      delay = 300;

      disable = {
        ft = [ ];  # filetypes
        bt = [ ];  # buftypes
      };
    };
  };
}

