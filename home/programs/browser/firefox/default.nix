{inputs, pkgs, theme, config, ...}:
{
  programs.firefox =
  {
    enable = true;
    profiles."main" = {
      isDefault = true;
      id = 0;
      name = "main";

      # addons
      extensions = import ./addons { inherit inputs pkgs; };

      # custom search engines, default, etc.
      search.engines = import ./searchEngines { inherit pkgs; };
      search = {
        force = true;
        default = "duckduckgo";
        order = [ "Annas-Archive" "NixOS Wiki" "Nix Packages" "Nix Options" "Home-Manager" "StackOverflow" "Github" "fmhy" ];
      };

      # theme for the firefox ui
      userChrome = import ./userChrome { inherit theme pkgs; };

      # theme for the content firefox presents.
      userContent = import ./userContent { inherit theme; };

      # settings for firefox. telemetry, scrolling, etc.
      settings = import ./settings { inherit theme; };
    };
    profiles."minimal" = {
      isDefault = false;
      id = 1;
      name = "minimal";

      # addons
      extensions = import ./addons/minimal.nix { inherit inputs pkgs; };

      # custom search engines, default, etc.
      search.engines = import ./searchEngines { inherit pkgs; };
      search = {
        force = true;
        default = "duckduckgo";
        order = [ "Annas-Archive" "NixOS Wiki" "Nix Packages" "Nix Options" "Home-Manager" "StackOverflow" "Github" "fmhy" ];
      };

      # theme for the firefox ui
      userChrome = import ./userChrome { inherit theme pkgs; };

      # theme for the content firefox presents.
      userContent = import ./userContent { inherit theme; };

      # settings for firefox. telemetry, scrolling, etc.
      settings = import ./settings { inherit theme; };
    };
    profiles."testing" = {
      isDefault = false;
      id = 2;
      name = "testing";

      # addons
      extensions = import ./addons/minimal.nix { inherit inputs pkgs; };

      # custom search engines, default, etc.
      search.engines = import ./searchEngines { inherit pkgs; };
      search = {
        force = true;
        default = "duckduckgo";
        order = [ "Annas-Archive" "NixOS Wiki" "Nix Packages" "Nix Options" "Home-Manager" "StackOverflow" "Github" "fmhy" ];
      };

      # theme for the firefox ui
      userChrome = import ./userChrome/testing.nix { inherit theme pkgs; };

      # theme for the content firefox presents.
      userContent = import ./userContent/minimal.nix { inherit pkgs theme; };

      settings = import ./settings/minimal.nix { inherit theme; };
    };
  };

  xdg.desktopEntries = {
    firefox-minimal = {
      name = "Firefox-minimal";
      genericName = "Web Browser";
      exec = "firefox -p minimal %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = [ "Application" "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
    firefox-testing = {
      name = "firefox-testing";
      genericName = "Web Browser";
      exec = "firefox -p testing %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = [ "Application" "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
  };




}
