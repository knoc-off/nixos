{
  pkgs,
  lib,
  color-lib,
  theme,
  ...
}:
let
  # Highlight groups that share identical settings, keyed by group name.
  mkGroup = names: attrs: lib.genAttrs names (_: attrs);
in
{
  colorschemes.onedark = {
    enable = true;
    settings = rec {
      style = "dark";
      transparent = true;
      term_colors = true;
      ending_tildes = false;
      cmp_itemkind_reverse = false;

      colors = {
        # Map theme colors to the colorscheme's expected color variables
        bg0 = "#${theme.dark.base00}"; # Background
        bg1 = "#${color-lib.adjustOkhslLightness 0.03 theme.dark.base00}"; # Slightly lighter background
        bg2 = "#${color-lib.adjustOkhslLightness 0.06 theme.dark.base00}"; # Even lighter background
        bg3 = "#${color-lib.adjustOkhslLightness 0.09 theme.dark.base00}"; # Lightest background

        fg = "#${theme.dark.base05}"; # Foreground text

        # Core syntax colors
        grey = "#${theme.dark.base03}"; # Comments, subtle UI elements
        light_grey = "#${theme.dark.base04}"; # Lighter grey for punctuation

        red = "#${theme.dark.base08}"; # Errors, variables, deletion
        orange = "#${theme.dark.base09}"; # Numbers, booleans, constants
        yellow = "#${theme.dark.base0A}"; # Types, classes, attributes
        green = "#${theme.dark.base0B}"; # Strings, added lines
        cyan = "#${theme.dark.base0C}"; # Escape sequences, regex, markup
        blue = "#${theme.dark.base0D}"; # Functions, methods, headings
        purple = "#${theme.dark.base0E}"; # Keywords, special methods

        # Create variations using color-lib
        # dark_orange/green/blue and bright_red/green/blue/purple are unused --
        # onedark only reads dark_{red,yellow,cyan,purple} (diagnostics.darker,
        # on by default) and bright_{cyan,orange,yellow} (below).
        dark_red = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base08}";
        dark_yellow = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base0A}";
        dark_cyan = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base0C}";
        dark_purple = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base0E}";

        bright_orange = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base09}";
        bright_yellow = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base0A}";
        bright_cyan = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base0C}";

        # Specialized/desaturated colors for specific UI elements
        diff_add = "#${color-lib.adjustOkhslSaturation (-0.2) theme.dark.base0B}";
        diff_change = "#${color-lib.adjustOkhslSaturation (-0.2) theme.dark.base0D}";
        diff_delete = "#${color-lib.adjustOkhslSaturation (-0.2) theme.dark.base08}";
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
          fg = "$bright_yellow";
        };
        Visual = {
          bg = "$bg3";
        };
        Cursor = {
          fg = "$bg0";
          bg = "$bright_cyan";
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
          bg = "#${color-lib.setOkhslLightness 0.15 theme.dark.base0B}";
        };
        DiffChange = {
          fg = "$blue";
          bg = "#${color-lib.setOkhslLightness 0.15 theme.dark.base0D}";
        };
        DiffDelete = {
          fg = "$red";
          bg = "#${color-lib.setOkhslLightness 0.15 theme.dark.base08}";
        };
        DiffText = {
          fg = "$fg";
          bg = "#${color-lib.setOkhslLightness 0.25 theme.dark.base0E}";
        };

        # Syntax Highlighting
        Identifier = {
          fg = "$fg";
          fmt = "${code_style.variables}";
        };
      }
      // mkGroup
        [
          "Statement"
          "Keyword"
          "Conditional"
          "Repeat"
          "Label"
          "Operator"
          "Exception"
        ]
        {
          fg = "$purple";
          fmt = "${code_style.keywords}";
        }
      // mkGroup [
        "PreProc"
        "Include"
        "Define"
        "Macro"
      ] { fg = "$purple"; }
      // mkGroup [
        "Type"
        "StorageClass"
        "Structure"
        "Typedef"
      ] { fg = "$yellow"; }
      // {
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

        # mini.pick fuzzy finder
        MiniPickNormal = {
          fg = "$fg";
          bg = "$bg1";
        };
        MiniPickBorder = {
          fg = "$bg3";
          bg = "$bg1";
        };
        MiniPickBorderText = {
          fg = "$purple";
          bg = "$bg1";
        };
        MiniPickPrompt = {
          fg = "$blue";
          bg = "$bg1";
        };
        MiniPickMatchCurrent = {
          fg = "$fg";
          bg = "$bg3";
          fmt = "bold";
        };
        MiniPickMatchMarked = {
          fg = "$orange";
        };
        MiniPickMatchRanges = {
          fg = "$orange";
        };
        MiniPickPreviewLine = {
          bg = "$bg2";
        };
        MiniPickPreviewRegion = {
          bg = "$bg3";
        };
        MiniPickIconFile = {
          fg = "$fg";
        };
        MiniPickIconDirectory = {
          fg = "$blue";
        };
        # Blink.cmp completion menu
        BlinkCmpMenu = {
          fg = "$fg";
          bg = "$bg1";
        };
        BlinkCmpMenuSelection = {
          fg = "$bg0";
          bg = "$blue";
        };
        BlinkCmpLabel = {
          fg = "$fg";
        };
        BlinkCmpLabelMatch = {
          fg = "$blue";
        };
        BlinkCmpKindFunction = {
          fg = "$blue";
        };
        BlinkCmpKindMethod = {
          fg = "$blue";
        };
        BlinkCmpKindVariable = {
          fg = "$cyan";
        };
        BlinkCmpKindField = {
          fg = "$red";
        };
        BlinkCmpKindKeyword = {
          fg = "$purple";
        };
        BlinkCmpKindText = {
          fg = "$cyan";
        };
        BlinkCmpKindInterface = {
          fg = "$cyan";
        };
        BlinkCmpGhostText = {
          fg = "$grey";
        };

        # Indent-blankline plugin highlights
        IblIndent = {
          fg = "$bg2"; # subtle indent guides
        };

        # Dimmed rainbow indent guides (parent scope hierarchy)
      }
      // lib.mapAttrs' (name: base: {
        name = "IblRainbow${name}";
        value = {
          fg = "#${color-lib.setOkhslLightness 0.25 theme.dark.${base}}";
          nocombine = true;
        };
      }) {
        Red = "base08";
        Yellow = "base0A";
        Blue = "base0D";
        Orange = "base09";
        Green = "base0B";
        Violet = "base0E";
        Cyan = "base0C";
      }
      // {
        # vim-matchup - bright active pair highlighting
        MatchWord = {
          fg = "$bright_cyan";
          fmt = "bold,underline";
        };
        MatchWordCur = {
          fg = "$bright_cyan";
          fmt = "bold,underline";
        };
        MatchParenCur = {
          fg = "$bright_orange";
          fmt = "bold";
        };
      }
      // mkGroup [
        "Number"
        "Boolean"
        "Float"
      ] { fg = "$orange"; };
    };
  };
}
