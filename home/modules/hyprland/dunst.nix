{ pkgs, theme, config, ... }:
{
  services.dunst = {
    enable = true;
    settings =
      {
        global = {
          width = 300;
          height = 300;
          offset = "30x50";
          origin = "top-right";
          transparency = 10;
          frame_color = "#${theme.base03}";
          font = "Droid Sans 9"; # config.fontProfiles.regular.family; #"Droid Sans 9";
        };
        urgency_normal = {
          background = "#${theme.base00}";
          foreground = "#${theme.white00}";
          timeout = 10;
        };
      };
  };
}
