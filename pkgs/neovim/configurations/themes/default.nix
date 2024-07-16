{ pkgs, lib, ... }:
{
  colorschemes.tokyonight = {
    enable = true;
    settings = {
      style = "storm";
      transparent = true;
      terminal_colors = true;
      styles = {
        comments = { italic = true; };
        keywords = { italic = true; };
        functions = { };
        variables = { };
        sidebars = "dark";
        floats = "dark";
      };
    };
  };

  extraConfigLua = ''
    local colors = require("tokyonight.colors").setup()

    require("tokyonight").setup({
      on_colors = function(c)
        -- You can modify colors here
        c.bg = "#000000"
      end,
      on_highlights = function(hl, c)
        -- Customize highlights here
        hl.TelescopeMatching = { fg = c.orange }
        hl.TelescopeSelection = { fg = c.fg, bg = c.bg_dark, bold = true }
        hl.TelescopePromptPrefix = { bg = c.bg_dark }
        hl.TelescopePromptNormal = { bg = c.bg_dark }
        hl.TelescopeResultsNormal = { bg = c.bg_dark }
        hl.TelescopePreviewNormal = { bg = c.bg_dark }
        hl.TelescopePromptBorder = { bg = c.bg_dark, fg = c.bg_dark }
        hl.TelescopeResultsBorder = { bg = c.bg_dark, fg = c.bg_dark }
        hl.TelescopePreviewBorder = { bg = c.bg_dark, fg = c.bg_dark }
        hl.TelescopePromptTitle = { bg = c.purple, fg = c.bg_dark }
        hl.TelescopeResultsTitle = { fg = c.bg_dark }
        hl.TelescopePreviewTitle = { bg = c.green, fg = c.bg_dark }
        hl.CmpItemKindField = { bg = c.red, fg = c.bg_dark }
        hl.PMenu = { bg = "NONE" }
      end,
    })

    vim.cmd[[colorscheme tokyonight]]
  '';
}
