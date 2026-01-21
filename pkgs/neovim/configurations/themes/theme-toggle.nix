{
  theme,
  color-lib,
  lib,
  ...
}: {
  extraConfigLuaPre = let
    darkTheme = theme.dark;
    lightTheme = theme.light;
  in ''
    _G.theme_dark = {
      style = "dark",
      transparent = true,
      colors = {
        bg0 = "#${darkTheme.base00}",
        bg1 = "#${color-lib.adjustOkhslLightness 0.03 darkTheme.base00}",
        bg2 = "#${color-lib.adjustOkhslLightness 0.06 darkTheme.base00}",
        bg3 = "#${color-lib.adjustOkhslLightness 0.09 darkTheme.base00}",
        fg = "#${darkTheme.base05}",
        grey = "#${darkTheme.base03}",
        light_grey = "#${darkTheme.base04}",
        red = "#${darkTheme.base08}",
        orange = "#${darkTheme.base09}",
        yellow = "#${darkTheme.base0A}",
        green = "#${darkTheme.base0B}",
        cyan = "#${darkTheme.base0C}",
        blue = "#${darkTheme.base0D}",
        purple = "#${darkTheme.base0E}",
        dark_red = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base08}",
        dark_orange = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base09}",
        dark_yellow = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0A}",
        dark_green = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0B}",
        dark_cyan = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0C}",
        dark_blue = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0D}",
        dark_purple = "#${color-lib.adjustOkhslLightness (-0.1) darkTheme.base0E}",
        bright_red = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base08}",
        bright_orange = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base09}",
        bright_yellow = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0A}",
        bright_green = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0B}",
        bright_cyan = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0C}",
        bright_blue = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0D}",
        bright_purple = "#${color-lib.adjustOkhslLightness 0.1 darkTheme.base0E}",
        diff_add = "#${color-lib.adjustOkhslSaturation (-0.2) darkTheme.base0B}",
        diff_change = "#${color-lib.adjustOkhslSaturation (-0.2) darkTheme.base0D}",
        diff_delete = "#${color-lib.adjustOkhslSaturation (-0.2) darkTheme.base08}",
      }
    }

    _G.theme_light = {
      style = "light",
      transparent = false,
      colors = {
        bg0 = "#${lightTheme.base00}",
        bg1 = "#${color-lib.adjustOkhslLightness (-0.03) lightTheme.base00}",
        bg2 = "#${color-lib.adjustOkhslLightness (-0.06) lightTheme.base00}",
        bg3 = "#${color-lib.adjustOkhslLightness (-0.09) lightTheme.base00}",
        fg = "#${lightTheme.base05}",
        grey = "#${lightTheme.base03}",
        light_grey = "#${lightTheme.base04}",
        red = "#${lightTheme.base08}",
        orange = "#${lightTheme.base09}",
        yellow = "#${lightTheme.base0A}",
        green = "#${lightTheme.base0B}",
        cyan = "#${lightTheme.base0C}",
        blue = "#${lightTheme.base0D}",
        purple = "#${lightTheme.base0E}",
        dark_red = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base08}",
        dark_orange = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base09}",
        dark_yellow = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0A}",
        dark_green = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0B}",
        dark_cyan = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0C}",
        dark_blue = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0D}",
        dark_purple = "#${color-lib.adjustOkhslLightness (-0.1) lightTheme.base0E}",
        bright_red = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base08}",
        bright_orange = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base09}",
        bright_yellow = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0A}",
        bright_green = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0B}",
        bright_cyan = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0C}",
        bright_blue = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0D}",
        bright_purple = "#${color-lib.adjustOkhslLightness 0.1 lightTheme.base0E}",
        diff_add = "#${color-lib.adjustOkhslSaturation (-0.2) lightTheme.base0B}",
        diff_change = "#${color-lib.adjustOkhslSaturation (-0.2) lightTheme.base0D}",
        diff_delete = "#${color-lib.adjustOkhslSaturation (-0.2) lightTheme.base08}",
      }
    }

    -- Track current theme
    _G.current_theme_mode = "dark"

    -- Function to toggle between light and dark themes
    _G.toggle_theme = function()
      local onedark = require('onedark')

      if _G.current_theme_mode == "dark" then
        onedark.setup(_G.theme_light)
        onedark.load()
        _G.current_theme_mode = "light"
        vim.notify("Switched to light theme", vim.log.levels.INFO)
      else
        onedark.setup(_G.theme_dark)
        onedark.load()
        _G.current_theme_mode = "dark"
        vim.notify("Switched to dark theme", vim.log.levels.INFO)
      end
    end
  '';

  keymaps = [
    {
      mode = "n";
      key = "<leader>tt";
      action = lib.nixvim.mkRaw "_G.toggle_theme";
      options = {
        silent = true;
        desc = "Toggle between light and dark theme";
      };
    }
  ];
}
