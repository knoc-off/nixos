{
  pkgs,
  lib,
  color-lib,
  theme,
  ...
}: let
  # Generate highlights for all theme colors
  flattenThemeToHighlights = attrPrefix: attrs:
    lib.foldl' (
      acc: name: let
        value = attrs.${name};
        attrPath =
          if attrPrefix == ""
          then name
          else "${attrPrefix}_${name}";
      in
        if builtins.isString value
        then
          acc
          // {
            ${attrPath} = {
              bg = "#${value}";
              fg = "#${color-lib.ensureTextContrast value value 4.5}";
            };
          }
        else acc // flattenThemeToHighlights attrPath value
    ) {} (builtins.attrNames attrs);

  themeHighlights = flattenThemeToHighlights "theme" theme;
in {
  colorschemes.onedark = {
    enable = true;
    settings = rec {
      style = "dark";
      transparent = true;
      term_colors = true;
      ending_tildes = false;
      cmp_itemkind_reverse = false;
      toggle_style_key = "<leader>ts";

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
        dark_red = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base08}";
        dark_orange = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base09}";
        dark_yellow = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base0A}";
        dark_green = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base0B}";
        dark_cyan = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base0C}";
        dark_blue = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base0D}";
        dark_purple = "#${color-lib.adjustOkhslLightness (-0.1) theme.dark.base0E}";

        bright_red = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base08}";
        bright_orange = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base09}";
        bright_yellow = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base0A}";
        bright_green = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base0B}";
        bright_cyan = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base0C}";
        bright_blue = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base0D}";
        bright_purple = "#${color-lib.adjustOkhslLightness 0.1 theme.dark.base0E}";

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

      highlights =
        {
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
            fg = "$bg2"; # subtle indent guides
          };

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

          # Custom highlights from core.nix
          TODO = {
            fg = "$bg0";
            bg = "#${color-lib.setOkhsvValue 0.9 theme.dark.base0A}";
          };
          FIXME = {
            fg = "$bg0";
            bg = "#${color-lib.setOkhsvValue 0.9 theme.dark.base0E}";
          };
          HACK = {
            fg = "$bg0";
            bg = "#${color-lib.setOkhsvValue 0.9 theme.dark.base0C}";
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
        }
        // themeHighlights;
    };
  };
}
# { theme, pkgs, lib, ... }: {
#   colorschemes.base16 = {
#     enable = true;
#
#     # Define your custom colorscheme here
#     colorscheme = {
#       # --- Replace these placeholder hex codes with your desired colors ---
#       base00 = "#${theme.dark.base00}"; # #1d2021 Default Background
#       base01 = "#${theme.dark.base01}"; # #3c3836 Lighter Background (Status Bar)
#       base02 = "#${theme.dark.base02}"; # #504945 Selection Background
#       base03 = "#${theme.dark.base03}"; # #665c54 Comments, Invisibles, Line Highlighting
#       base04 = "#${theme.dark.base04}"; # #bdae93 Dark Foreground (Status Bar)
#       base05 = "#${theme.dark.base05}"; # #d5c4a1 Default Foreground, Caret, Delimiters, Operators
#       base06 = "#${theme.dark.base06}"; # #ebdbb2 Light Foreground (Not often used)
#       base07 = "#${theme.dark.base07}"; # #fbf1c7 Light Background (Not often used)
#       base08 = "#${theme.dark.base08}"; # #fb4934 Variables, XML Tags, Markup Link Text, Markup Lists, Diff Deleted
#       base09 = "#${theme.dark.base09}"; # #fe8019 Integers, Boolean, Constants, XML Attributes, Markup Link Url
#       base0A = "#${theme.dark.base0A}"; # #fabd2f Classes, Markup Bold, Search Text Background
#       base0B = "#${theme.dark.base0B}"; # #b8bb26 Strings, Inherited Class, Markup Code, Diff Inserted
#       base0C = "#${theme.dark.base0C}"; # #8ec07c Support, Regular Expressions, Escape Characters, Markup Quotes
#       base0D = "#${theme.dark.base0D}"; # #83a598 Functions, Methods, Attribute IDs, Headings
#       base0E = "#${theme.dark.base0E}"; # #d3869b Keywords, Storage, Selector, Markup Italic, Diff Changed
#       base0F = "#${theme.dark.base0F}"; # #d65d0e Deprecated, Opening/Closing Embedded Language Tags e.g. <?php ?>
#       # --- End of custom color definitions ---
#     };
#
#     # Optional: Configure integrations (defaults are shown in the plugin definition)
#     settings = {
#        telescope = true;
#        telescope_borders = true;
#     #   indentblankline = true;
#     #   notify = true;
#     #   ts_rainbow = true;
#     #   cmp = true;
#     #   illuminate = true;
#     #   lsp_semantic = true;
#     #   mini_completion = true;
#     #   dapui = true;
#      };
#
#     # Optional: Set to false if you don't want base16 to theme your status bar
#     # setUpBar = true;
#   };
#
#   # Ensure termguicolors is enabled for base16 to work correctly
#   # (The plugin sets this by default, but explicitly setting it doesn't hurt)
#   opts.termguicolors = true;
#
#   # Set the colorscheme globally (Nixvim handles applying the base16 config)
#   # Although the plugin definition sets `colorscheme = null;` internally
#   # to prevent default loading, we still need to tell Vim *which*
#   # colorscheme configuration Nixvim should apply.
#   # colorscheme = "base16";
# }

