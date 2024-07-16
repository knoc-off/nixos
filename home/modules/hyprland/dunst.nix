{theme, ...}: {
  services.dunst = {
    enable = true;
    settings = {
      global = {
        width = 300;
        height = 300;
        offset = "30x50";
        origin = "top-right";
        corner_radius = 5;

        # progress bar
        progress_bar_corner_radius = 5;

        # transparency = 10; # x11 only
        frame_color = "#${theme.base02}";
        font = "Droid Sans 9"; # config.fontProfiles.regular.family; #"Droid Sans 9";
      };
      urgency_normal = {
        background = "#${theme.base00}";
        foreground = "#${theme.white00}";
        highlight = "#${theme.blue00}";
        timeout = 10;
      };
      urgency_critical = {
        background = "#${theme.red03}";
        foreground = "#${theme.white00}";
        highlight = "#${theme.red00}";
        timeout = 0;
      };
    };
  };
}
