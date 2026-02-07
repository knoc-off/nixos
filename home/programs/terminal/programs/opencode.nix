{
  theme,
  color-lib,
  upkgs,
  pkgs,
  lib,
  ...
}: {
  programs.opencode = let
    inherit (color-lib) setOkhslLightness setOkhslSaturation;
    lighten = setOkhslLightness 0.7;
    saturate = setOkhslSaturation 0.9;

    sa = hex: lighten (saturate hex);
  in {
    enable = true;
    package = upkgs.opencode;
    themes.customtheme = {
      "$schema" = "https://opencode.ai/theme.json";
      defs = {
        base00 = "#${theme.dark.base00}";
        base00-1 = "#${color-lib.adjustOkhslLightness 0.03 theme.dark.base00}";
        base00-2 = "#${color-lib.adjustOkhslLightness 0.06 theme.dark.base00}";
        base00-3 = "#${color-lib.adjustOkhslLightness 0.09 theme.dark.base00}";
        base01 = "#${theme.dark.base01}";
        base02 = "#${theme.dark.base02}";
        base03 = "#${theme.dark.base03}";
        base04 = "#${theme.dark.base04}";
        base05 = "#${theme.dark.base05}";
        base06 = "#${theme.dark.base06}";
        base07 = "#${theme.dark.base07}";
        base08 = "#${sa theme.dark.base08}";
        diffremoved = "#${color-lib.mixColors (color-lib.setOkhslLightness 0.2 theme.dark.base08) theme.dark.base00 0.1}";
        #diffremoved = "#${color-lib.mixColors (color-lib.adjustOkhslLightness 0.03 theme.dark.base00) theme.dark.base08 0.3}";
        base09 = "#${sa theme.dark.base09}";
        base0A = "#${sa theme.dark.base0A}";
        base0B = "#${sa theme.dark.base0B}";
        #diffadded = "#${color-lib.mixColors (color-lib.adjustOkhslLightness 0.03 theme.dark.base00) theme.dark.base0B 0.3}";
        #diffadded = "#${color-lib.setOkhslLightness 0.2 theme.dark.base0B}";
        diffadded = "#${color-lib.mixColors (color-lib.setOkhslLightness 0.2 theme.dark.base0B) theme.dark.base00 0.1}";
        base0C = "#${sa theme.dark.base0C}";
        base0D = "#${sa theme.dark.base0D}";
        base0E = "#${sa theme.dark.base0E}";
        base0F = "#${theme.dark.base0F}";
      };
      theme = {
        primary = {
          dark = "base0D";
          light = "base0D";
        };
        secondary = {
          dark = "base0E";
          light = "base0E";
        };
        accent = {
          dark = "base0C";
          light = "base0C";
        };
        error = {
          dark = "base08";
          light = "base08";
        };
        warning = {
          dark = "base09";
          light = "base09";
        };
        success = {
          dark = "base0B";
          light = "base0B";
        };
        info = {
          dark = "base0D";
          light = "base0D";
        };

        text = {
          dark = "base06";
          light = "base00";
        };
        textMuted = {
          dark = "base05";
          light = "base03";
        };
        background = {
          dark = "base00";
          light = "base07";
        };
        backgroundPanel = {
          dark = "base00-1";
          light = "base06";
        };
        backgroundElement = {
          dark = "base00-2";
          light = "base05";
        };

        border = {
          dark = "base01";
          light = "base04";
        };
        borderActive = {
          dark = "base02";
          light = "base03";
        };
        borderSubtle = {
          dark = "base00-3";
          light = "base04";
        };

        diffAdded = {
          dark = "base0B";
          light = "base0B";
        };
        diffRemoved = {
          dark = "base08";
          light = "base08";
        };
        diffContext = {
          dark = "base07";
          light = "base03";
        };
        diffHunkHeader = {
          dark = "base0C"; #!!!
          light = "base03";
        };
        diffHighlightAdded = {
          dark = "base0B";
          light = "base0B";
        };
        diffHighlightRemoved = {
          dark = "base08";
          light = "base08";
        };
        diffAddedBg = {
          dark = "diffadded";
          light = "base06";
        };
        diffRemovedBg = {
          dark = "diffremoved";
          light = "base06";
        };
        diffContextBg = {
          dark = "base00-2";
          light = "base06";
        };
        diffLineNumber = {
          dark = "base02";
          light = "base05";
        };
        diffAddedLineNumberBg = {
          dark = "base00-2"; # TODO
          light = "base06";
        };
        diffRemovedLineNumberBg = {
          dark = "base00-2"; # TODO
          light = "base06";
        };

        markdownText = {
          dark = "base05";
          light = "base00";
        };
        markdownHeading = {
          dark = "base0D";
          light = "base0D";
        };
        markdownLink = {
          dark = "base0E";
          light = "base0E";
        };
        markdownLinkText = {
          dark = "base0C";
          light = "base0C";
        };
        markdownCode = {
          dark = "base0B";
          light = "base0B";
        };
        markdownBlockQuote = {
          dark = "base00-2";
          light = "base03";
        };
        markdownEmph = {
          dark = "base09";
          light = "base09";
        };
        markdownStrong = {
          dark = "base0A";
          light = "base0A";
        };
        markdownHorizontalRule = {
          dark = "base0D";
          light = "base03";
        };
        markdownListItem = {
          dark = "base0D";
          light = "base0D";
        };
        markdownListEnumeration = {
          dark = "base0C";
          light = "base0C";
        };
        markdownImage = {
          dark = "base0E";
          light = "base0E";
        };
        markdownImageText = {
          dark = "base0C";
          light = "base0C";
        };
        markdownCodeBlock = {
          dark = "base05";
          light = "base00";
        };

        syntaxComment = {
          dark = "base0E"; # !!!
          light = "base03";
        };
        syntaxKeyword = {
          dark = "base0E";
          light = "base0E";
        };
        syntaxFunction = {
          dark = "base0D";
          light = "base0D";
        };
        syntaxVariable = {
          dark = "base0C";
          light = "base0C";
        };
        syntaxString = {
          dark = "base0B";
          light = "base0B";
        };
        syntaxNumber = {
          dark = "base0F";
          light = "base0F";
        };
        syntaxType = {
          dark = "base0C";
          light = "base0C";
        };
        syntaxOperator = {
          dark = "base0E";
          light = "base0E";
        };
        syntaxPunctuation = {
          dark = "base05";
          light = "base00";
        };
      };
    };

    settings = {
      theme = "customtheme";

      keybinds = {
        leader = "ctrl+x";
        app_exit = "ctrl+c,ctrl+d,<leader>q";
        editor_open = "<leader>e";
        theme_list = "<leader>t";
        sidebar_toggle = "<leader>b";
        scrollbar_toggle = "none";
        username_toggle = "none";
        status_view = "<leader>s";
        session_export = "<leader>x";
        session_new = "<leader>n";
        session_list = "<leader>l";
        session_timeline = "<leader>g";
        session_fork = "none";
        session_rename = "none";
        session_share = "none";
        session_unshare = "none";
        session_interrupt = "escape";
        session_compact = "<leader>c";
        messages_page_up = "pageup";
        messages_page_down = "pagedown";
        messages_half_page_up = "ctrl+alt+u";
        messages_half_page_down = "ctrl+alt+d";
        messages_first = "ctrl+g,home";
        messages_last = "ctrl+alt+g,end";
        messages_last_user = "none";
        messages_copy = "<leader>y";
        messages_undo = "<leader>u";
        messages_redo = "<leader>r";
        messages_toggle_conceal = "<leader>h";
        tool_details = "none";
        model_list = "<leader>m";
        model_cycle_recent = "f2";
        model_cycle_recent_reverse = "shift+f2";
        model_cycle_favorite = "none";
        model_cycle_favorite_reverse = "none";
        command_list = "ctrl+p";
        agent_list = "<leader>a";
        agent_cycle = "tab";
        agent_cycle_reverse = "shift+tab";
        input_clear = "ctrl+c";
        input_paste = "ctrl+v";
        input_submit = "shift+return,ctrl+return,super+return";
        input_newline = "return";
        input_move_left = "left,ctrl+b";
        input_move_right = "right,ctrl+f";
        input_move_up = "up";
        input_move_down = "down";
        input_select_left = "shift+left";
        input_select_right = "shift+right";
        input_select_up = "shift+up";
        input_select_down = "shift+down";
        input_line_home = "ctrl+a";
        input_line_end = "ctrl+e";
        input_select_line_home = "ctrl+shift+a";
        input_select_line_end = "ctrl+shift+e";
        input_visual_line_home = "alt+a";
        input_visual_line_end = "alt+e";
        input_select_visual_line_home = "alt+shift+a";
        input_select_visual_line_end = "alt+shift+e";
        input_buffer_home = "home";
        input_buffer_end = "end";
        input_select_buffer_home = "shift+home";
        input_select_buffer_end = "shift+end";
        input_delete_line = "ctrl+shift+d";
        input_delete_to_line_end = "ctrl+k";
        input_delete_to_line_start = "ctrl+u";
        input_backspace = "backspace,shift+backspace";
        input_delete = "ctrl+d,delete,shift+delete";
        input_undo = "ctrl+-,super+z";
        input_redo = "ctrl+.,super+shift+z";
        input_word_forward = "alt+f,alt+right,ctrl+right";
        input_word_backward = "alt+b,alt+left,ctrl+left";
        input_select_word_forward = "alt+shift+f,alt+shift+right";
        input_select_word_backward = "alt+shift+b,alt+shift+left";
        input_delete_word_forward = "alt+d,alt+delete,ctrl+delete";
        input_delete_word_backward = "ctrl+w,ctrl+backspace,alt+backspace";
        history_previous = "up";
        history_next = "down";
        session_child_cycle = "<leader>right";
        session_child_cycle_reverse = "<leader>left";
        terminal_suspend = "ctrl+z";
        terminal_title_toggle = "none";
      };
      permission = {
        edit = "ask";
        bash = "ask";
      };
      mcp = {
        context7 = {
          type = "remote";
          url = "https://mcp.context7.com/mcp";
          headers = {
            CONTEXT7_API_KEY = "ctx7sk-aa86d2c2-ca7e-489c-a0ee-65733a066c8b";
          };
          enabled = true;
        };
        ddog = {
          type = "remote";
          url = "https://mcp.datadoghq.eu/api/unstable/mcp-server/mcp";
          oauth = {
            scope = "openid";
          };
        };
      };
    };
  };
}
