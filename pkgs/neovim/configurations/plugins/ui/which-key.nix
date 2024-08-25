{
  plugins.which-key = {
    enable = true;
    plugins = {
      registers = true;
      spelling = {
        enabled = true;
        suggestions = 20;
      };
      presets = {
        operators = true;
        motions = true;
        textObjects = true;
        windows = true;
        nav = true;
        z = true;
        g = true;
      };
    };
    operators = { gc = "Comments"; };
    keyLabels = {
      "<space>" = "SPC";
      "<cr>" = "RET";
      "<tab>" = "TAB";
    };
    motions.count = true;
    icons = {
      breadcrumb = "»";
      separator = "➜";
      group = "+";
    };
    popupMappings = {
      scrollDown = "<c-d>";
      scrollUp = "<c-u>";
    };
    window = {
      border = "single";
      position = "bottom";
      margin = {
        top = 1;
        right = 0;
        bottom = 1;
        left = 0;
      };
      padding = {
        top = 1;
        right = 2;
        bottom = 1;
        left = 2;
      };
      winblend = 0;
    };
    layout = {
      height = {
        min = 4;
        max = 25;
      };
      width = {
        min = 20;
        max = 50;
      };
      spacing = 3;
      align = "left";
    };
    ignoreMissing = false;
    showHelp = true;
    showKeys = true;
    triggers = "auto";
    triggersNoWait = [ "`" "'" "g`" "g'" "<c-r>" "z=" ];
    triggersBlackList = {
      i = [ "j" "k" ];
      v = [ "j" "k" ];
    };
    disable = {
      buftypes = [ ];
      filetypes = [ ];
    };
  };

}
