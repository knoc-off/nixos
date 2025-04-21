{ config, color-lib, lib, theme, ... }:
{
  plugins.highlight-colors = {
    enable = true;

    # All configuration options go under settings
    settings = {
      # Choose rendering style
      render = "background";

      # Enable color formats you need
      enable_hex = true;
      enable_named_colors = true;

      # Custom colors with properly escaped labels
      custom_colors = let
        mkThemeColors = themeSet:
          lib.mapAttrsToList (name: value: {
            # Construct the label string: "theme.<key>"
            label = "theme.${name}";
            # Construct the color string: "#<value>"
            color = "#${value}";
          }) themeSet;
      in [
        {
          label = "%-%-primary";
          color = "#${theme.base0D}";
        }
        {
          label = "%-%-secondary";
          color = "#${theme.base0B}";
        }
        {
          label = "%-%-warning";
          color = "#${theme.base0C}";
        }
        {
          label = "%-%-error";
          color = "#${theme.base08}";
        }
      ] ++ (mkThemeColors theme);
    };

    # Optional cmp integration at the plugin level
    # cmpIntegration = true;
  };
}
