{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.programs.firefox;
  
  addons = inputs.firefox-addons.packages.${pkgs.system};

  firefox-csshacks = pkgs.stdenv.mkDerivation {
    name = "patched-firefox-csshacks";
    src = inputs.firefox-csshacks;
    installPhase = ''
      cp -r . $out
    '';
  };

  # Simplified search engines configuration
  searchConfig = {
    force = lib.mkOverride 1000 true;
    default = "DuckDuckGo";
    order = ["DuckDuckGo" "Nix Packages" "NixOS Wiki" "GitHub"];
    engines = {
      "Nix Packages" = {
        urls = [{
          template = "https://search.nixos.org/packages";
          params = [
            {
              name = "type";
              value = "packages";
            }
            {
              name = "query";
              value = "{searchTerms}";
            }
          ];
        }];
        definedAliases = ["@np"];
      };

      "NixOS Wiki" = {
        urls = [{
          template = "https://nixos.wiki/index.php";
          params = [{
            name = "search";
            value = "{searchTerms}";
          }];
        }];
        definedAliases = ["@nw"];
      };

      "GitHub" = {
        urls = [{
          template = "https://github.com/search";
          params = [{
            name = "q";
            value = "{searchTerms}";
          }];
        }];
        definedAliases = ["@gh"];
      };

      # Disable default search engines
      "Bing".metaData.hidden = true;
      "Google".metaData.hidden = true;
      "Amazon".metaData.hidden = true;
    };
  };

  # Minimal userChrome - only essential customizations
  userChrome = ''
    /* Import necessary CSS hacks */
    @import "${firefox-csshacks}/chrome/autohide_sidebar.css";
    @import "${firefox-csshacks}/chrome/hide_tabs_toolbar_v2.css";

    /* Sidebar customization */
    #sidebar-box {
      min-width: 38px !important;
      --uc-autohide-sidebar-delay: 100ms !important;
      --uc-autohide-transition-duration: 200ms !important;
      --uc-sidebar-width: 38px !important;
      --uc-sidebar-hover-width: 25vw !important;
      --uc-autohide-transition-type: ease-in-out !important;
    }

    /* Remove the sidebar header */
    #sidebar-header {
      display: none;
    }

    /* Hide native tabs (useful with Sidebery extension) */
    #TabsToolbar {
      visibility: collapse;
    }

    /* Hide window controls */
    .titlebar-buttonbox-container,
    .titlebar-spacer[type="post-tabs"] {
      display: none;
    }
  '';

  # Minimal userContent - only new tab page background color override
  userContent = ''
    /* Apply to all about: pages, including about:home and about:newtab */
    @-moz-document url-prefix("about:") {
      #root,
      .newtab-main,
      .outer-wrapper {
        background-color: #1b2429 !important;
      }

      /* Remove background images from new tab page */
      .wallpaper-input[style*="background-image"] {
        background-image: none !important;
      }
    }
  '';

  # Minimal settings
  settings = {
    # Core functionality
    "extensions.autoDisableScopes" = 0;
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
    
    # Performance
    "gfx.webrender.all" = true;
    "layers.async-pan-zoom.enabled" = true;
    
    # Theme
    "devtools.theme" = "dark";
    "extensions.activeThemeID" = "firefox-compact-dark@mozilla.org";
    
    # UI customization
    "browser.tabs.insertAfterCurrent" = true;
    "browser.urlbar.showSearchSuggestionsFirst" = false;
    
    # Privacy
    "extensions.pocket.enabled" = false;
    "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
    
    # Smooth scrolling
    "general.autoScroll" = true;
    "general.smoothScroll.msdPhysics.enabled" = true;
  };
in {
  home.sessionVariables = {
    BROWSER = "firefox";
  };

  programs.firefox = {
    enable = true;
    
    profiles = {
      "main" = {
        isDefault = true;
        id = 0;
        name = "main";

        extensions.packages = with addons; [
          # Essential
          ublock-origin
          bitwarden
          sidebery
          tridactyl
          
          # Privacy
          smart-referer
          cookie-autodelete
        ];

        inherit userChrome userContent settings;
        search = searchConfig;
      };
    };
  };

  # Auto generate desktop entries for each profile (Linux only)
  xdg.desktopEntries = lib.mkIf pkgs.stdenv.isLinux {
    firefox-main = {
      name = "Firefox";
      genericName = "Web Browser";
      exec = "${pkgs.firefox}/bin/firefox -P main";
      icon = "${pkgs.firefox}/lib/firefox/browser/chrome/icons/default/default128.png";
      type = "Application";
      categories = ["Network" "WebBrowser"];
      mimeType = ["text/html" "text/xml"];
    };

    firefox-private = {
      name = "Firefox Private";
      genericName = "Web Browser";
      exec = "${pkgs.firefox}/bin/firefox --private-window";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      type = "Application";
      categories = ["Network" "WebBrowser"];
      mimeType = ["text/html" "text/xml"];
    };
  };
}
