{
  pkgs,
  lib,
  color-lib,
  theme,
  ...
}: {
  colorschemes.onedark = {
    enable = true;
    settings = rec {
      style = "light";
      transparent = false;
      term_colors = true;
      ending_tildes = false;
      cmp_itemkind_reverse = false;
      toggle_style_key = "<leader>ts";

      colors = {
        # Map theme colors to the colorscheme's expected color variables <theme.light.base00>
        bg0 = "#${theme.light.base00}"; # Background
        bg1 = "#${color-lib.adjustOkhslLightness (-0.03) theme.light.base00}"; # Slightly darker background for light mode
        bg2 = "#${color-lib.adjustOkhslLightness (-0.06) theme.light.base00}"; # Even darker background
        bg3 = "#${color-lib.adjustOkhslLightness (-0.09) theme.light.base00}"; # Darkest background for selections

        fg = "#${theme.light.base05}"; # Foreground text

        # Core syntax colors
        grey = "#${theme.light.base03}"; # Comments, subtle UI elements
        light_grey = "#${theme.light.base04}"; # Lighter grey for punctuation

        red = "#${theme.light.base08}"; # Errors, variables, deletion
        orange = "#${theme.light.base09}"; # Numbers, booleans, constants
        yellow = "#${theme.light.base0A}"; # Types, classes, attributes
        green = "#${theme.light.base0B}"; # Strings, added lines
        cyan = "#${theme.light.base0C}"; # Escape sequences, regex, markup
        blue = "#${theme.light.base0D}"; # Functions, methods, headings
        purple = "#${theme.light.base0E}"; # Keywords, special methods

        # Create variations using color-lib
        dark_red = "#${color-lib.adjustOkhslLightness (-0.1) theme.light.base08}";
        dark_orange = "#${color-lib.adjustOkhslLightness (-0.1) theme.light.base09}";
        dark_yellow = "#${color-lib.adjustOkhslLightness (-0.1) theme.light.base0A}";
        dark_green = "#${color-lib.adjustOkhslLightness (-0.1) theme.light.base0B}";
        dark_cyan = "#${color-lib.adjustOkhslLightness (-0.1) theme.light.base0C}";
        dark_blue = "#${color-lib.adjustOkhslLightness (-0.1) theme.light.base0D}";
        dark_purple = "#${color-lib.adjustOkhslLightness (-0.1) theme.light.base0E}";

        bright_red = "#${color-lib.adjustOkhslLightness 0.1 theme.light.base08}";
        bright_orange = "#${color-lib.adjustOkhslLightness 0.1 theme.light.base09}";
        bright_yellow = "#${color-lib.adjustOkhslLightness 0.1 theme.light.base0A}";
        bright_green = "#${color-lib.adjustOkhslLightness 0.1 theme.light.base0B}";
        bright_cyan = "#${color-lib.adjustOkhslLightness 0.1 theme.light.base0C}";
        bright_blue = "#${color-lib.adjustOkhslLightness 0.1 theme.light.base0D}";
        bright_purple = "#${color-lib.adjustOkhslLightness 0.1 theme.light.base0E}";

        # Specialized/desaturated colors for specific UI elements
        diff_add = "#${color-lib.adjustOkhslSaturation (-0.2) theme.light.base0B}";
        diff_change = "#${color-lib.adjustOkhslSaturation (-0.2) theme.light.base0D}";
        diff_delete = "#${color-lib.adjustOkhslSaturation (-0.2) theme.light.base08}";
      };

      code_style = {
        comments = "italic";
        keywords = "italic";
        functions = "none";
        strings = "none";
        variables = "none";
        constants = "none";
      };

      highlights = {
        # Basic UI Elements
        Normal = {
          fg = "$fg";
          bg = "$bg0";
        };
        NormalFloat = {
          fg = "$fg";
          bg = "$bg1";
        };
        Comment = {
          fg = "$grey";
          fmt = "${code_style.comments}";
        };
        LineNr = {
          fg = "$grey";
        };
        CursorLineNr = {
          fg = "$dark_yellow";
        };
        Visual = {
          bg = "$bg3";
        };
        VisualNOS = {
          bg = "$bg3";
        };
        Search = {
          fg = "$bg0";
          bg = "$orange";
        };
        IncSearch = {
          fg = "$bg0";
          bg = "$orange";
        };
        CursorLine = {
          bg = "$bg1";
        };
        CursorColumn = {
          bg = "$bg1";
        };
        ColorColumn = {
          bg = "$bg1";
        };
        SignColumn = {
          fg = "$fg";
        };
        StatusLine = {
          fg = "$fg";
          bg = "$bg2";
        };
        StatusLineNC = {
          fg = "$grey";
          bg = "$bg1";
        };
        VertSplit = {
          fg = "$bg3";
        };
        MatchParen = {
          fg = "$orange";
          fmt = "bold,underline";
        };

        # Popup Menus
        Pmenu = {
          fg = "$fg";
          bg = "$bg1";
        };
        PmenuSel = {
          fg = "$bg0";
          bg = "$blue";
        };
        PmenuSbar = {
          bg = "$bg1";
        };
        PmenuThumb = {
          bg = "$grey";
        };

        # Folds and Spell Checking
        Folded = {
          fg = "$grey";
          bg = "$bg1";
        };
        FoldColumn = {
          fg = "$grey";
          bg = "$bg0";
        };
        SpellBad = {
          fg = "$red";
          fmt = "underline";
        };
        SpellCap = {
          fg = "$blue";
          fmt = "underline";
        };
        SpellRare = {
          fg = "$purple";
          fmt = "underline";
        };
        SpellLocal = {
          fg = "$cyan";
          fmt = "underline";
        };

        # Diff Highlighting
        DiffAdd = {
          fg = "$green";
          bg = "#${color-lib.setOkhslLightness 0.85 theme.light.base0B}";
        };
        DiffChange = {
          fg = "$blue";
          bg = "#${color-lib.setOkhslLightness 0.85 theme.light.base0D}";
        };
        DiffDelete = {
          fg = "$red";
          bg = "#${color-lib.setOkhslLightness 0.85 theme.light.base08}";
        };
        DiffText = {
          fg = "$fg";
          bg = "#${color-lib.setOkhslLightness 0.75 theme.light.base0E}";
        };

        # Syntax Highlighting
        Identifier = {
          fg = "$fg";
          fmt = "${code_style.variables}";
        };
        Statement = {
          fg = "$purple";
          fmt = "${code_style.keywords}";
        };
        Keyword = {
          fg = "$purple";
          fmt = "${code_style.keywords}";
        };
        Conditional = {
          fg = "$purple";
          fmt = "${code_style.keywords}";
        };
        Repeat = {
          fg = "$purple";
          fmt = "${code_style.keywords}";
        };
        Label = {
          fg = "$purple";
          fmt = "${code_style.keywords}";
        };
        Operator = {
          fg = "$purple";
          fmt = "${code_style.keywords}";
        };
        Exception = {
          fg = "$purple";
          fmt = "${code_style.keywords}";
        };
        PreProc = {
          fg = "$purple";
        };
        Include = {
          fg = "$purple";
        };
        Define = {
          fg = "$purple";
        };
        Macro = {
          fg = "$purple";
        };
        Type = {
          fg = "$yellow";
        };
        StorageClass = {
          fg = "$yellow";
        };
        Structure = {
          fg = "$yellow";
        };
        Typedef = {
          fg = "$yellow";
        };
        Special = {
          fg = "$orange";
        };
        SpecialChar = {
          fg = "$red";
        };
        Tag = {
          fg = "$blue";
        };
        Delimiter = {
          fg = "$light_grey";
        };
        SpecialComment = {
          fg = "$grey";
          fmt = "${code_style.comments}";
        };
        Todo = {
          fg = "$red";
          fmt = "${code_style.comments}";
        };
        Function = {
          fg = "$blue";
          fmt = "${code_style.functions}";
        };
        String = {
          fg = "$green";
          fmt = "${code_style.strings}";
        };
        Character = {
          fg = "$green";
        };
        Number = {
          fg = "$orange";
        };
        Boolean = {
          fg = "$orange";
        };
        Float = {
          fg = "$orange";
        };
        Constant = {
          fg = "$orange";
          fmt = "${code_style.constants}";
        };

        # Messages and Errors
        Error = {
          fg = "$red";
        };
        ErrorMsg = {
          fg = "$red";
        };
        WarningMsg = {
          fg = "$yellow";
        };
        MoreMsg = {
          fg = "$blue";
        };
        Question = {
          fg = "$cyan";
        };

        # Git and Diff Highlighting
        GitSignsAdd = {
          fg = "$green";
        };
        GitSignsChange = {
          fg = "$blue";
        };
        GitSignsDelete = {
          fg = "$red";
        };

        # Telescope customizations (from your original config)
        TelescopeMatching = {
          fg = "$orange";
        };
        TelescopeSelection = {
          fg = "$fg";
          bg = "$bg1";
          bold = true;
        };
        TelescopePromptPrefix = {
          bg = "$bg1";
        };
        TelescopePromptNormal = {
          bg = "$bg1";
        };
        TelescopeResultsNormal = {
          bg = "$bg1";
        };
        TelescopePreviewNormal = {
          bg = "$bg1";
        };
        TelescopePromptBorder = {
          fg = "$bg1";
          bg = "$bg1";
        };
        TelescopeResultsBorder = {
          fg = "$bg1";
          bg = "$bg1";
        };
        TelescopePreviewBorder = {
          fg = "$bg1";
          bg = "$bg1";
        };
        TelescopePromptTitle = {
          fg = "$bg0";
          bg = "$purple";
        };
        TelescopeResultsTitle = {
          fg = "$bg0";
        };
        TelescopePreviewTitle = {
          fg = "$bg0";
          bg = "$green";
        };
        CmpItemKindField = {
          fg = "$bg0";
          bg = "$red";
        };
        PMenu = {
          bg = "NONE";
        };

        # Additional CMP styling
        CmpItemAbbr = {
          fg = "$fg";
        };
        CmpItemAbbrMatch = {
          fg = "$blue";
        };
        CmpItemAbbrMatchFuzzy = {
          fg = "$blue";
        };
        CmpItemKindVariable = {
          fg = "$bg0";
          bg = "$cyan";
        };
        CmpItemKindInterface = {
          fg = "$bg0";
          bg = "$cyan";
        };
        CmpItemKindText = {
          fg = "$bg0";
          bg = "$cyan";
        };
        CmpItemKindFunction = {
          fg = "$bg0";
          bg = "$blue";
        };
        CmpItemKindMethod = {
          fg = "$bg0";
          bg = "$blue";
        };
        CmpItemKindKeyword = {
          fg = "$bg0";
          bg = "$purple";
        };
        CmpItemKindProperty = {
          fg = "$bg0";
          bg = "$purple";
        };
        CmpItemKindUnit = {
          fg = "$bg0";
          bg = "$purple";
        };

        # Indent-blankline plugin highlights
        IblIndent = {
          fg = "$bg3";
        };
        IblScope = {
          fg = "$red";
        };

        # Custom highlights from core.nix
        TODO = {
          fg = "$bg0";
          bg = "#${color-lib.setOkhsvValue 0.9 theme.light.base0A}";
        };
        FIXME = {
          fg = "$bg0";
          bg = "#${color-lib.setOkhsvValue 0.9 theme.light.base0E}";
        };
        HACK = {
          fg = "$bg0";
          bg = "#${color-lib.setOkhsvValue 0.9 theme.light.base0C}";
        };
        SnippetCursor = {
          fg = "$bg0";
          bg = "$green";
        };
        ExtraWhitespace = {
          bg = "$bg1";
        };
        ahhhhh = {
          fg = "$bg0";
          bg = "$red";
        };

        # RainbowDelimiterRed
        # RainbowDelimiterYellow
        # RainbowDelimiterBlue
        # RainbowDelimiterOrange
        # RainbowDelimiterGreen
        # RainbowDelimiterViolet
        # RainbowDelimiterCyan
      };
    };
  };
}
