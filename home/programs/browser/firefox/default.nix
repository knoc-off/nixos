{
  inputs,
  pkgs,
  theme,
  lib,
  ...
}:
let
  mkFirefoxSettings = import ./settings/mkFirefoxSettings.nix { inherit lib theme; };
  mkUserChrome = import ./mkUserChrome.nix { inherit pkgs theme; };
  mkUserContent = import ./mkUserContent.nix { inherit pkgs theme; };
in

{
  programs.firefox = {
    enable = true;
    profiles."main" = {
      isDefault = true;
      id = 0;
      name = "main";

      # addons
      extensions = import ./addons {inherit inputs pkgs;};

      # custom search engines, default, etc.
      search.engines = import ./searchEngines {inherit pkgs;};
      search = {
        force = true;
        default = "duckduckgo";
        order = ["Annas-Archive" "NixOS Wiki" "Nix Packages" "Nix Options" "Home-Manager" "StackOverflow" "Github" "fmhy"];
      };

      # theme for the firefox ui
      #userChrome = import ./userChrome {inherit theme pkgs;};
      userChrome = mkUserChrome {
        enableSidebarCustomization = true;
        enableTabsCustomization = true;
        enableColorScheme = true;
        enableAutohideFeatures = true;
        extraStyles = ''
          /* Any additional custom styles */
        '';
      };

      # theme for the content firefox presents.
      userContent = mkUserContent {
        removeFlash = true;

      };

      # settings for firefox. telemetry, scrolling, etc.
      #settings = import ./settings;

      settings = mkFirefoxSettings {
        enableSmoothScroll = true;
        enableDarkTheme = true;
        enablePrivacy = true;
        enablePerformance = true;
        enableCustomUI = true;
      };
    };
    profiles."minimal" = {
      isDefault = false;
      id = 1;
      name = "minimal";

      # addons
      extensions = import ./addons/minimal.nix {inherit inputs pkgs;};

      # custom search engines, default, etc.
      search.engines = import ./searchEngines {inherit pkgs;};
      search = {
        force = true;
        default = "duckduckgo";
        order = ["Annas-Archive" "NixOS Wiki" "Nix Packages" "Nix Options" "Home-Manager" "StackOverflow" "Github" "fmhy"];
      };

      userChrome = mkUserChrome {
        enableSidebarCustomization = true;
        enableTabsCustomization = true;
        enableColorScheme = true;
        enableAutohideFeatures = true;
        extraStyles = ''
          /* Any additional custom styles */
        '';
      };

      # theme for the content firefox presents.
      userContent = mkUserContent {
        removeFlash = true;
      };

      # settings for firefox. telemetry, scrolling, etc.
      #settings = import ./settings;
      settings = mkFirefoxSettings {
        enableSmoothScroll = true;
        enablePrivacy = true;
        extraSettings = {
          # Add any additional settings specific to the minimal profile
          "browser.tabs.loadInBackground" = false;
        };
      };
    };
  };

  xdg.desktopEntries = {
    firefox-minimal = {
      name = "Firefox-minimal";
      genericName = "Web Browser";
      exec = "firefox -p minimal %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = ["Application" "Network" "WebBrowser"];
      mimeType = ["text/html" "text/xml"];
    };
    firefox-private = {
      name = "firefox private";
      genericName = "Web Browser";
      exec = "firefox --private-window %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = ["Application" "Network" "WebBrowser"];
      mimeType = ["text/html" "text/xml"];
    };
  };
}
