{
  lib,
  pkgs,
  config,
  ...
}:
with lib; let
  # Shorter name to access final settings a
  # user of hello.nix module HAS ACTUALLY SET.
  # cfg is a typical convention.
  # unsigned int
  id = 0;

  # computers name
  profileName = "main";

  # Your firefox install path
  firefoxPath = ".mozilla/firefox";

  # The location of your firefox config
  profilePath = "${firefoxPath}/${profileName}";

  # Firefox Addons, may want to change this at some point
  addons = inputs.firefox-addons.packages.${pkgs.system};

  # can add these to a flake.
  # shold link these a directory back, so that it can be reused.
  Edge-Mimicry = pkgs.fetchFromGitHub {
    owner = "UnlimitedAvailableUsername";
    repo = "Edge-Mimicry-Tree-Style-Tab-For-Firefox";
    rev = "f9c59082c4803aace8c07fe9888b0216e9e680a7";
    sha256 = "sha256-dEaWqwbui70kCzBeNjJIttKSSgi4rAncc8tGcpGvpl4=";
  };

  firefox-csshacks = pkgs.fetchFromGitHub {
    owner = "MrOtherGuy";
    repo = "firefox-csshacks";
    rev = "67a9e9f9c96e6d007b4c57f1dd7eaceaee135178";
    sha256 = "sha256-uz6tqkjjTFMvY6IY70ke8dW5nst0AJoWJHObtzalQAc=";
  };

  cfg = config.services.firefoxBrowser;
in {
  # Declare what settings a user of this "hello.nix" module CAN SET.
  options.services.firefoxBrowser = {
    enable = mkEnableOption "Firfox browser";
    profileName = mkOption {
      type = types.str;
      default = "main";
      description = ''
        The name of the profile to use.
      '';
    };

    # privacy options
    privacy = {
      # disable telemetry
      telemetry = mkOption {
        type = types.bool;
        default = true;
        description = ''
          telemetry.
        '';
      };

      # disable crash reports
      crashReports = mkOption {
        type = types.bool;
        default = true;
        description = ''
          crash reports.
        '';
      };

      # disable health reports
      healthReports = mkOption {
        type = types.bool;
        default = true;
        description = ''
          health reports.
        '';
      };

      # disable experiments
      experiments = mkOption {
        type = types.bool;
        default = true;
        description = ''
          experiments.
        '';
      };

      # disable search suggestions
      searchSuggestions = mkOption {
        type = types.bool;
        default = true;
        description = ''
          search suggestions, autocomplete.
        '';
      };

      # pocket
      pocket = mkOption {
        type = types.bool;
        default = false;
        description = ''
          pocket.
        '';
      };

      # firefox accounts
      firefoxAccounts = mkOption {
        type = types.bool;
        default = true;
        description = ''
          disable firefox accounts.
        '';
      };
    };

    visual = {
      removeWhiteFlash = mkOption {
        type = types.bool;
        default = true;
        description = ''
          removes the white flash when loading a page.
        '';
      };

      # sidebar
      sidebar-styles = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable sidebar styles
        '';
      };

      # Remove this?
      darken-everything = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable a dark theme, that may not be stable.
          sites may break!
        '';
      };
    };

    # search engine
    searchEngine = mkOption {
      type = types.str;
      default = "duckduckgo";
      description = ''
        The search engine to use.
      '';
    };
  };

  # Declare settings for firefox
  config = mkIf cfg.enable {
    # if tridactyl plugin is enabled
    home.packages = [
      pkgs.tridactyl-native
    ];

    programs.firefox = {
      package = pkgs.firefox.override {
        # See nixpkgs' firefox/wrapper.nix to check which options you can use
        nativeMessagingHosts = [
          # Gnome shell native connector
          #pkgs.gnome-browser-connector
          # Tridactyl native connector
          pkgs.tridactyl-native
        ];
      };

      profiles.${profileName} = {
        isDefault = true;
        inherit id;
        name = "${profileName}";

        extensions = with addons; [
          # Privacy and Security
          ublock-origin
          bitwarden

          # Appearance / functionality
          sidebery
          darkreader
          nighttab

          # Privacy / Security
          smart-referer
          history-cleaner # deletes history older than <time>

          # Quality of life
          translate-web-pages
          export-cookies-txt # exports cookies to a txt file, used for curl, etc.

          istilldontcareaboutcookies # deletes popups, not super needed with ublock.
          cookie-autodelete # deletes cookies when tab is closed

          tridactyl # best vim plugin
          #forget_me_not # deletes all website data

          violentmonkey
        ];

        search = {
          engines = {
            "Nix Packages" = {
              urls = [
                {
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
                    {
                      name = "channel";
                      value = "unstable";
                    }
                    {
                      name = "size";
                      value = "150";
                    }
                  ];
                }
              ];
              icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/package.svg";
              definedAliases = ["!p"];
            };
            "Nix Options" = {
              urls = [
                {
                  template = "https://search.nixos.org/options";
                  params = [
                    {
                      name = "type";
                      value = "packages";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                    {
                      name = "channel";
                      value = "unstable";
                    }
                    {
                      name = "size";
                      value = "150";
                    }
                  ];
                }
              ];

              icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/cm_options.svg";
              definedAliases = ["!o"];
            };

            "NixOS Wiki" = {
              urls = [
                {
                  template = "https://nixos.wiki/index.php";
                  params = [
                    {
                      name = "search";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              #iconUpdateURL = "https://nixos.wiki/favicon.png";
              #updateInterval = 24 * 60 * 60 * 1000; # every day
              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = ["!n"];
            };

            "fmhy" = {
              urls = [
                {
                  template = "https://www.fmhy.tk/search";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "${pkgs.circle-flags}/share/circle-flags-svg/other/pirate.svg";
              definedAliases = ["!f"];
            };

            "StackOverflow" = {
              urls = [
                {
                  template = "https://duckduckgo.com/";
                  params = [
                    {
                      name = "q";
                      value = "site%3Astackoverflow.com+{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/stackoverflow.svg";
              definedAliases = ["!s"];
            };

            "Github" = {
              urls = [
                {
                  template = "https://duckduckgo.com/";
                  params = [
                    {
                      name = "q";
                      value = "site%3Agithub.com+-issues+-topic+-releases+{searchTerms}";
                    }
                  ];
                }
              ];
              #iconUpdateURL = "https://nixos.wiki/favicon.png";
              #updateInterval = 24 * 60 * 60 * 1000; # every day
              icon = "${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/github.svg";
              definedAliases = ["!g"];
            };

            "Home-Manager" = {
              urls = [{template = "https://mipmip.github.io/home-manager-option-search/?query={searchTerms}";}];
              updateInterval = 24 * 60 * 60 * 1000; # every day
              icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/twitter-home.svg";
              definedAliases = ["!h"];
            };

            "Bing".metaData.hidden = true;
            "Google".metaData.hidden = true;
            "Amazon.de".metaData.hidden = true;
            "Wikipidia (en)".metaData.hidden = true;
            "DuckDuckGo".metaData.hidden = false;
          };
          force = true;
          default = "duckduckgo";
        };

        # Change all relative paths to absolute paths
        userChrome = ''
          @import "./firefox-csshacks/chrome/autohide_sidebar.css";

          /* override sidebar options */
          /* https://pastebin.com/KFHjwR4d */
          #sidebar-box{
            --uc-autohide-sidebar-delay: 100ms;
            --uc-autohide-transition-duration: 115ms;
            --uc-sidebar-width: var(--sidebar-width);
            --uc-sidebar-hover-width: 25vw;
            background-color: #${theme.base02} !important;
          }

          /* this is url bar options */
          :root {
              --sidebar-width: 40px;
              --panel-width: 100vw; /* url bar width */
              --panel-hide-offset: -30px;
              --opacity-when-hidden: 0.0;
          }

          /* this removes the sidebar header */
          #sidebar-header {
              display: none
          }

          /* not sure. i think it removes the url bar */
          * {
            background-color: #${theme.hp} !important;
            -moz-appearance: none !important;
          }

          .tabbrowser-tabpanels {
              background-color: #${theme.base02} !important;
          }
          browser {
              background-color: #${theme.base02} !important;
          }

          #bookmarksPanel, #history-panel {
            background-color: #${theme.base01} !important;
          }

          #sidebar-header,#sidebar-search-container,#bookmarks-view-children,#historyTree {
            color: #${theme.base01} !important;
            background-color: #${theme.base01} !important;
            -moz-appearance:none !important;
            border-color:transparent !important;
          }


          .sidebar-panel #search-box{
            background-color: #${theme.base03} !important;
            color: #${theme.base06} !important;
          }

          #sidebar,
          #sidebar-header {
            background-color: #${theme.base02} !important;
            border-bottom: none !important;
            background-image: var(--lwt-additional-images);
            background-position: auto;
            background-size: auto;
            background-repeat: no-repeat;
          }

          /* what does this do. */
          /*
          #browser {
            --sidebar-border-color: #${theme.base01} !important;
          }
          #sidebar-header::before {
            background-color: #${theme.base02} !important;
          }

          #sidebar-header::after{
            background-color: #${theme.base02} !important;
          }
          */

          /* hides the native tabs */
          #TabsToolbar {
            visibility: collapse;
          }

          /* Hide window controls */
          .titlebar-buttonbox-container{
            display:none
          }
          .titlebar-spacer[type="post-tabs"]{
            display:none
          }

          /* Color Configs */
          /* should try to remove &/or debug */
          :root{
            -moz-border-radius: 1em;
            /* Popup panels */
            --arrowpanel-background: #${theme.base01} !important;
            --arrowpanel-border-color: #${theme.base00} !important;
            --arrowpanel-color: #${theme.base06} !important;
            --arrowpanel-dimmed: #${theme.base05} !important;

            /* window and toolbar background */
            --lwt-accent-color: #${theme.base01} !important;
            --lwt-accent-color-inactive: #${theme.base00} !important;
            --toolbar-bgcolor: #${theme.base01} !important;

            /* tabs with system theme - text is not controlled by variable */
            --tab-selected-bgcolor: #${theme.base02} !important;

            /* tabs with any other theme */
            --lwt-text-color: #${theme.base05} !important;
            --lwt-selected-tab-background-color: #${theme.base02} !important;

            /* toolbar area */
            --toolbarbutton-icon-fill: #${theme.base06} !important;
            --lwt-toolbarbutton-hover-background: #${theme.base06} !important;
            --lwt-toolbarbutton-active-background: #${theme.base05} !important;

            /* urlbar */
            --toolbar-field-border-color: #${theme.base04} !important;
            --toolbar-field-focus-border-color: #${theme.base05} !important;
            --urlbar-popup-url-color: #${theme.base06} !important;

            /* urlbar Firefox < 92 */
            --lwt-toolbar-field-background-color: #${theme.base02} !important;
            --lwt-toolbar-field-focus: #${theme.base07} !important;
            --lwt-toolbar-field-color: #${theme.base06} !important;
            --lwt-toolbar-field-focus-color: #${theme.base07} !important;

            /* urlbar Firefox 92+ */
            --toolbar-field-background-color: #${theme.base02} !important;
            --toolbar-field-focus-background-color: #${theme.base03} !important;
            --toolbar-field-color: #${theme.base06} !important;
            --toolbar-field-focus-color: #${theme.base07} !important;

            /* sidebar - note the sidebar-box rule for the header-area */
            --lwt-sidebar-background-color: #${theme.base02} !important;
            --lwt-sidebar-text-color: #${theme.base06} !important;
          }

          /* line between nav-bar and tabs toolbar,
          also fallback color for border around selected tab */
          #navigator-toolbox{ --lwt-tabs-border-color: #${theme.base02} !important; }
          /* Line above tabs */
          #tabbrowser-tabs{ --lwt-tab-line-color: #${theme.base05} !important; }
          /* the header-area of sidebar needs this to work */
          #sidebar-box{ --sidebar-background-color: #${theme.base00} !important; }

          /* This changes the color of the loading page */
          #tabbrowser-tabpanels,
          #webextpanels-window,
          #webext-panels-stack,
          #webext-panels-browser {
            background: #${theme.base02} !important;
          }




          /* Auto-hide address bar */
          #navigator-toolbox{
            position: fixed !important;
            /* Comment out following line to get 'slide-page-down' reveal, like in F11 fullscreen mode */
            display: block;
            transition: margin-top 82ms 33ms linear, opacity 82ms 33ms linear !important;
            z-index: 1;
            opacity: 1;
            /* Spacing on the left for sidebar */
            margin-left: var(--sidebar-width);
            /* Disabled the borders, as the bottom one seemed to have unwanted top padding sometimes */
            border: none !important;
          }

          #navigator-toolbox,
          #navigator-toolbox > *{
            /* calculate pannel width minus --uc-sidebar-width */
             width: calc(var(--panel-width) - var(--sidebar-width));
          }

          /* if the cursor is at the top 30px of the screen, show the toolbar */
          /* and if the cursor is at the left half of the screen show the toolbar */
          #navigator-toolbox:not(:focus-within):not(:hover){
            margin-top: var(--panel-hide-offset);
            /* Hide the toolbar when not hovered */
            opacity: var(--opacity-when-hidden);
          }


          /* Disable auto-hiding when in 'customize' mode */
          :root[customizing] #navigator-toolbox{
            position: relative !important;
            opacity: 1 !important;
            margin-top: 0px;
          }



          :root[tabsintitlebar] {
            appearance: -moz-win-glass!important;
          }

        '';

        /*
        # this fades from black to white, would be perfect to remove the white flash
          @-webkit-keyframes blackWhiteFade {
            0% { background-color: black; }
            100% { background-color: white; }
          }

          .blinkdiv {
            height: 100px;
            background-color: white;
            -webkit-animation-name: blackWhiteFade;
            -webkit-animation-iteration-count: 1;
            -webkit-animation-duration: 10s;
          }
        */

        userContent = ''
          .tabbrowser-tabbox {
              background-color: #${theme.base02} !important;
          }

          @-moz-document plain-text-document(), media-document(all) {
            @media (prefers-color-scheme: dark) {
              :root {
                background-color: #${theme.base02} !important;
                foreground-color: #${theme.base07} !important;
              }
              body:not([style*="background"], [class], [id]) {
                background-color: transparent !important;
              }
            }
          }

          /* Color Configs */
          /* not sure how i feel about this, because its hard to tell what is what */
          /* and themes can have unintended effects. */
          /* would be cool if with the theme.nix, if i could generate new colors from that */
          /* how would that work? deriviation that generates it would make the most sense */
          /* need to find a program that works like that. */
          /* like theme.mkshades, or something, and then have one color with many shades. */
          :root {
            /* this effects text color in firefox menus. */
            --in-content-page-color: #${theme.white00} !important;
            --in-content-page-background: #${theme.base00} !important;
            --in-content-text-color: #${theme.white02} !important;
            --in-content-selected-text: #${theme.white01} !important;
            --in-content-box-background: #${theme.base00} !important;
            --in-content-box-background-odd: #${theme.base00} !important;
            --in-content-box-background-hover: #${theme.base01} !important;
            --in-content-box-background-active: #${theme.base01} !important;
            --in-content-box-border-color: #${theme.cyan00} !important;
            --in-content-item-hover: #${theme.base01} !important;
            --in-content-item-selected: #${theme.base01} !important;
            --in-content-border-highlight: #${theme.cyan00} !important;
            --in-content-border-focus: #${theme.cyan00} !important;
            --in-content-border-hover: #${theme.cyan00} !important;
            --in-content-border-active: #${theme.cyan00} !important;
            --in-content-border-active-shadow: transparent !important;
            --in-content-border-invalid: #${theme.red00} !important;
            --in-content-border-invalid-shadow: #${theme.red02};
            --in-content-border-color: #${theme.cyan02} !important;
            --in-content-category-outline-focus: 1px dotted #${theme.cyan00} !important;
            --in-content-category-text-selected: #${theme.cyan00} !important;
            --in-content-category-text-selected-active: #${theme.cyan00} !important;
            --in-content-category-background-hover: #${theme.base00} !important;
            --in-content-category-background-active: #${theme.base00} !important;
            --in-content-category-background-selected-hover: #${theme.base00} !important;
            --in-content-category-background-selected-active: #${theme.base00} !important;
            --in-content-tab-color: #${theme.yellow00} !important;
            --in-content-link-color: #${theme.cyan02} !important;
            --in-content-link-color-hover: #${theme.cyan00} !important;
            --in-content-link-color-active: #${theme.cyan00} !important;
            --in-content-link-color-visited: #${theme.yellow00} !important;
            --in-content-button-background: var(--grey-90-a10);
            --in-content-button-background-hover: var(--grey-90-a20);
            --in-content-button-background-active: var(--grey-90-a30);
            --in-content-primary-button-background: var(--blue-60);
            --in-content-primary-button-background-hover: var(--blue-70);
            --in-content-primary-button-background-active: var(--blue-80);
            --in-content-table-background: transparent !important;
            --in-content-table-border-dark-color: #${theme.cyan02};
            --in-content-table-header-background: #${theme.blue01};
            --blue-40: #${theme.blue00};
            --blue-40-a10: rgb(69, 161, 255, 0.1);
            --blue-50: #${theme.blue01};
            --blue-50-a30: rgba(10, 132, 255, 0.3);
            --blue-60: #${theme.blue02} !important;
            --blue-70: #${theme.blue03} !important;
            --blue-80: #${theme.blue04} !important;
            --grey-20: #${theme.base01} !important; /* bg color 2 - ish*/
            --grey-30: #${theme.gray01} !important; /* text highlight color? */
            --grey-60: #${theme.gray03} !important;
            --grey-90: #${theme.gray04} !important; /* background bar, inspect menu */
            --grey-90-a10: #${theme.gray03} !important; /* drop shadow? */
            --grey-90-a20: #${theme.gray04} !important;
            --grey-90-a30: #${theme.gray05} !important;
            --grey-90-a40: #${theme.gray06} !important;
            --grey-90-a50: #${theme.gray06} !important;
            --red-50: #${theme.red00} !important;
            --red-50-a30: #${theme.red01} !important;
            --red-60: #${theme.red02} !important;
            --yellow-50: #${theme.yellow00} !important;
            --yellow-90: #${theme.yellow04} !important;
            --shadow-10: 0 1px 4px var(--grey-90-a10);
            --card-padding: 16px;
            --card-shadow: var(--shadow-10);
            --card-outline-color: var(--grey-30);
            --card-shadow-hover: var(--card-shadow), 0 0 0 5px var(--card-outline-color);
            --card-shadow-focus: 0 0 0 2px var(--blue-50), 0 0 0 6px var(--blue-50-a30);
          }


          :root{
            -moz-border-radius: 1em;

          }

          :root{
            -moz-border-radius: 1em;
            /* Popup panels */
            --arrowpanel-background: #${theme.base01} !important;
            --arrowpanel-border-color: #${theme.base00} !important;
            --arrowpanel-color: #${theme.base06} !important;
            --arrowpanel-dimmed: #${theme.base05} !important;

            /* window and toolbar background */
            --lwt-accent-color: #${theme.base01} !important;
            --lwt-accent-color-inactive: #${theme.base00} !important;
            --toolbar-bgcolor: #${theme.base01} !important;

            /* tabs with system theme - text is not controlled by variable */
            --tab-selected-bgcolor: #${theme.base02} !important;

            /* tabs with any other theme */
            --lwt-text-color: #${theme.base05} !important;
            --lwt-selected-tab-background-color: #${theme.base02} !important;

            /* toolbar area */
            --toolbarbutton-icon-fill: #${theme.base06} !important;
            --lwt-toolbarbutton-hover-background: #${theme.base06} !important;
            --lwt-toolbarbutton-active-background: #${theme.base05} !important;

            /* urlbar */
            --toolbar-field-border-color: #${theme.base04} !important;
            --toolbar-field-focus-border-color: #${theme.base05} !important;
            --urlbar-popup-url-color: #${theme.base06} !important;

            /* urlbar Firefox < 92 */
            --lwt-toolbar-field-background-color: #${theme.base02} !important;
            --lwt-toolbar-field-focus: #${theme.base07} !important;
            --lwt-toolbar-field-color: #${theme.base06} !important;
            --lwt-toolbar-field-focus-color: #${theme.base07} !important;

            /* urlbar Firefox 92+ */
            --toolbar-field-background-color: #${theme.base02} !important;
            --toolbar-field-focus-background-color: #${theme.base03} !important;
            --toolbar-field-color: #${theme.base06} !important;
            --toolbar-field-focus-color: #${theme.base07} !important;

            /* sidebar - note the sidebar-box rule for the header-area */
            --lwt-sidebar-background-color: #${theme.base02} !important;
            --lwt-sidebar-text-color: #${theme.base06} !important;
          }

          @-moz-document url("about:home"),url("about:blank"),url("about:newtab"),url("about:privatebrowsing"){
            body{background-color: #${theme.base02} !important }
          }

          @-moz-document url("about:preferences#home"){
            body{background-color: #${theme.base02} !important }
          }
        '';

        settings = import ./settings.nix {inherit theme;};
      };
    };
  };
}
