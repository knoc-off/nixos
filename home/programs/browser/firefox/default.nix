{ inputs, pkgs, theme, lib, ... }:
let

  firefox-csshacks = pkgs.stdenv.mkDerivation {
    name = "patched-firefox-csshacks";
    src = inputs.firefox-csshacks;

    #patches = [ ./patches/autohide_toolbox-zone.patch ];

    installPhase = ''
      cp -r . $out
    '';
  };

  mkFirefoxSettings =
    import ./settings/mkFirefoxSettings.nix { inherit lib theme; };
  mkUserChrome =
    import ./mkUserChrome.nix { inherit pkgs theme firefox-csshacks; };
  mkUserContent =
    import ./mkUserContent.nix { inherit pkgs theme firefox-csshacks; };

in {
  programs.firefox = {
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
        order = [
          "Annas-Archive"
          "NixOS Wiki"
          "Nix Packages"
          "Nix Options"
          "Home-Manager"
          "StackOverflow"
          "Github"
          "fmhy"
        ];
      };

      # theme for the firefox ui
      #userChrome = import ./userChrome {inherit theme pkgs;};
      userChrome = mkUserChrome {
        enableSidebarCustomization = true;
        hideTabs = true;
        enableColorScheme = false;
        autohideToolbox = true;
        autohideSidebar = true;
        extraStyles = ''
          /* Any additional custom styles */
        '';
      };

      # theme for the content firefox presents.
      userContent = mkUserContent { };

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
      extensions = import ./addons/minimal.nix { inherit inputs pkgs; };

      # custom search engines, default, etc.
      search.engines = import ./searchEngines { inherit pkgs; };
      search = {
        force = true;
        default = "duckduckgo";
        order = [
          "Annas-Archive"
          "NixOS Wiki"
          "Nix Packages"
          "Nix Options"
          "Home-Manager"
          "StackOverflow"
          "Github"
          "fmhy"
        ];
      };

      userChrome = mkUserChrome {
        enableSidebarCustomization = true;
        hideTabs = true;
        enableColorScheme = false;
        autohideToolbox = true;
        autohideSidebar = true;
        extraStyles = ''
          /* Any additional custom styles */
        '';
      };

      # theme for the content firefox presents.
      userContent = mkUserContent { removeFlash = true; };

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
    profiles."testing" = {
      isDefault = false;
      id = 2;
      name = "testing";

      userChrome = mkUserChrome {
        enableSidebarCustomization = false;
        hideTabs = false;
        enableColorScheme = false;
        autohideToolbox = false;
        autohideSidebar = false;
        extraStyles = ''
          @import "${firefox-csshacks}/chrome/autohide_main_toolbar.css";
        '';
      };

      userContent = mkUserContent { removeFlash = false; };

      settings = mkFirefoxSettings {
        enableSmoothScroll = true;
        enablePrivacy = true;
        extraSettings = {
          "browser.tabs.loadInBackground" = false;
        };
      };
    };
  };

  xdg.desktopEntries = {
    firefox-testing = {
      name = "Firefox-testing";
      genericName = "Web Browser";
      exec = "firefox -p testing %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = [ "Application" "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
    firefox-minimal = {
      name = "Firefox-minimal";
      genericName = "Web Browser";
      exec = "firefox -p minimal %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = [ "Application" "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
    firefox-private = {
      name = "firefox private";
      genericName = "Web Browser";
      exec = "firefox --private-window %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = [ "Application" "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
  };
}
