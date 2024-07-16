{ pkgs, lib, ... }: {
  colorschemes.onedark = {
    enable = true;
    settings = {
      style = "dark";
      transparent = true;
      term_colors = true;
      ending_tildes = false;
      cmp_itemkind_reverse = false;
      toggle_style_key = "<leader>ts";

      colors = {
        # bright_orange = "#ff8800";  # overrides
      };

      highlights = {
        TelescopeMatching = { fg = "$orange"; };
        TelescopeSelection = {
          fg = "$fg";
          bg = "$bg1";
          bold = true;
        };
        TelescopePromptPrefix = { bg = "$bg1"; };
        TelescopePromptNormal = { bg = "$bg1"; };
        TelescopeResultsNormal = { bg = "$bg1"; };
        TelescopePreviewNormal = { bg = "$bg1"; };
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
        TelescopeResultsTitle = { fg = "$bg0"; };
        TelescopePreviewTitle = {
          fg = "$bg0";
          bg = "$green";
        };
        CmpItemKindField = {
          fg = "$bg0";
          bg = "$red";
        };
        PMenu = { bg = "NONE"; };
      };
    };
  };
}
