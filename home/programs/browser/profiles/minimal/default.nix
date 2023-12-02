{ pkgs, config, inputs, lib, ... }:
let
  # unsigned int
  id = 1;

  # computers name
  profileName = "minimal";

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




in
{
  home.file = {
    "firefox-csshacks" = {
      source = "${firefox-csshacks}";
      target = "${profilePath}/chrome/firefox-csshacks";
    };
    "edge-mimicry" = {
      source = "${Edge-Mimicry}";
      target = "${profilePath}/chrome/edge-mimicry";
    };
  };

  #home.file."${profilePath}/chrome/sidebar-mods.css".text ;
  #home.file."${profilePath}/chrome/treestyletab-edge-mimicry.css".text ;

  programs.firefox = {
    profiles.${profileName} = {
      isDefault = true;
      inherit id;
      name = "${profileName}";

      extensions = with addons; [
        # Privacy and Security
        ublock-origin
        bitwarden

        # Appearance/functionality
        new-tab-override
        adsum-notabs

        smart-referer
        darkreader

        nighttab
        translate-web-pages
      ];


      search = {
        engines = {
          "Nix Packages" = {
            urls = [{
              template = "https://search.nixos.org/packages";
              params = [
                { name = "type"; value = "packages"; }
                { name = "query"; value = "{searchTerms}"; }
              ];
            }];

            icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
            definedAliases = [ "@np" ];
          };

          "NixOS Wiki" = {
            urls = [{ template = "https://nixos.wiki/index.php?search={searchTerms}"; }];
            iconUpdateURL = "https://nixos.wiki/favicon.png";
            updateInterval = 24 * 60 * 60 * 1000; # every day
            definedAliases = [ "@nw" ];
          };

          "Bing".metaData.hidden = true;
          "Google".metaData.hidden = true;
          "Amazon.se".metaData.hidden = true;
          "Wikipidia (en)".metaData.hidden = true;
          "DuckDuckGo".metaData.hidden = false;
        };
        force = true;
        default = "duckduckgo";

      };

      # @import "./edge-mimicry/edge-mimicry/sidebar-mods.css";
      userChrome = ''
        @import "./firefox-csshacks/chrome/autohide_sidebar.css";

        /* override sidebar options */
        /* https://pastebin.com/KFHjwR4d */
        #sidebar-box{
          --uc-autohide-sidebar-delay: 100ms;
          --uc-autohide-transition-duration: 115ms;
          --uc-sidebar-width: 40px;
        }


        .tabbrowser-tabpanels {
            background-color: #${config.colorScheme.colors.base02} !important;
        }
        browser {
            background-color: #${config.colorScheme.colors.base02} !important;
        }

        #bookmarksPanel, #history-panel {
          background-color: #${config.colorScheme.colors.base01} !important;
        }
        #sidebar-header,#sidebar-search-container,#bookmarks-view-children,#historyTree {
          color: #${config.colorScheme.colors.base01} !important;
          background-color: #${config.colorScheme.colors.base01} !important;
          -moz-appearance:none!important;
          border-color:transparent !important;
        }

        #sidebar-box{
          --sidebar-transition-delay: 100ms;
          --sidebar-width: 48px;
          --sidebar-hover-width: calc(calc(calc(var(--sidebar-width) - 0.65em) * 10) + 0.65em);
          --autohide-sidebar-delay: 100ms; /* Delay before hiding the sidebar */
          --sidebar-background-color: #${config.colorScheme.colors.base02} !important;
        }

        .sidebar-panel #search-box{
          background-color: #${config.colorScheme.colors.base03} !important;
          color: #${config.colorScheme.colors.base06} !important;
        }

        #sidebar,
        #sidebar-header {
          background-color: #${config.colorScheme.colors.base02} !important;
          border-bottom: none !important;
          background-image: var(--lwt-additional-images);
          background-position: auto;
          background-size: auto;
          background-repeat: no-repeat;
        }

        #browser {
          --sidebar-border-color: #${config.colorScheme.colors.base01} !important;
        }
        #sidebar-header::before {
          background-color: #${config.colorScheme.colors.base02} !important;
        }

        #sidebar-header::after{
          background-color: #${config.colorScheme.colors.base02} !important;
        }

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
        :root{
          -moz-border-radius: 1em;
          /* Popup panels */
          --arrowpanel-background: #${config.colorScheme.colors.base01} !important;
          --arrowpanel-border-color: #${config.colorScheme.colors.base00} !important;
          --arrowpanel-color: #${config.colorScheme.colors.base06} !important;
          --arrowpanel-dimmed: #${config.colorScheme.colors.base05} !important;

          /* window and toolbar background */
          --lwt-accent-color: #${config.colorScheme.colors.base01} !important;
          --lwt-accent-color-inactive: #${config.colorScheme.colors.base00} !important;
          --toolbar-bgcolor: #${config.colorScheme.colors.base01} !important;

          /* tabs with system theme - text is not controlled by variable */
          --tab-selected-bgcolor: #${config.colorScheme.colors.base02} !important;

          /* tabs with any other theme */
          --lwt-text-color: #${config.colorScheme.colors.base05} !important;
          --lwt-selected-tab-background-color: #${config.colorScheme.colors.base02} !important;

          /* toolbar area */
          --toolbarbutton-icon-fill: #${config.colorScheme.colors.base06} !important;
          --lwt-toolbarbutton-hover-background: #${config.colorScheme.colors.base06} !important;
          --lwt-toolbarbutton-active-background: #${config.colorScheme.colors.base05} !important;

          /* urlbar */
          --toolbar-field-border-color: #${config.colorScheme.colors.base04} !important;
          --toolbar-field-focus-border-color: #${config.colorScheme.colors.base05} !important;
          --urlbar-popup-url-color: #${config.colorScheme.colors.base06} !important;

          /* urlbar Firefox < 92 */
          --lwt-toolbar-field-background-color: #${config.colorScheme.colors.base02} !important;
          --lwt-toolbar-field-focus: #${config.colorScheme.colors.base07} !important;
          --lwt-toolbar-field-color: #${config.colorScheme.colors.base06} !important;
          --lwt-toolbar-field-focus-color: #${config.colorScheme.colors.base07} !important;

          /* urlbar Firefox 92+ */
          --toolbar-field-background-color: #${config.colorScheme.colors.base02} !important;
          --toolbar-field-focus-background-color: #${config.colorScheme.colors.base03} !important;
          --toolbar-field-color: #${config.colorScheme.colors.base06} !important;
          --toolbar-field-focus-color: #${config.colorScheme.colors.base07} !important;

          /* sidebar - note the sidebar-box rule for the header-area */
          --lwt-sidebar-background-color: #${config.colorScheme.colors.base02} !important;
          --lwt-sidebar-text-color: #${config.colorScheme.colors.base06} !important;
        }

        /* line between nav-bar and tabs toolbar,
        also fallback color for border around selected tab */
        #navigator-toolbox{ --lwt-tabs-border-color: #${config.colorScheme.colors.base02} !important; }
        /* Line above tabs */
        #tabbrowser-tabs{ --lwt-tab-line-color: #${config.colorScheme.colors.base05} !important; }
        /* the header-area of sidebar needs this to work */
        #sidebar-box{ --sidebar-background-color: #${config.colorScheme.colors.base00} !important; }

        /* This changes the color of the loading page */
        #tabbrowser-tabpanels,
        #webextpanels-window,
        #webext-panels-stack,
        #webext-panels-browser {
          background: #${config.colorScheme.colors.base02} !important;
        }


        /* Some variables for quick configuration - play with numbers to find a perfect match for your setup */
        :root {
            --sidebar-width: 0vw;
            --panel-width: 100vw;
            --panel-hide-offset: -30px;
            --opacity-when-hidden: 0.0;
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
          /* Reduced width for panel in order to not overflow the screen on the right side */
           width:  var(--panel-width);
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


        -moz-border-radius: 1em;

      '';
      userContent = ''
        .tabbrowser-tabbox {
            background-color: #${config.colorScheme.colors.base02} !important;
        }

        @-moz-document plain-text-document(), media-document(all) {
          @media (prefers-color-scheme: dark) {
            :root {
              background-color: #${config.colorScheme.colors.base02} !important;
            }
            body:not([style*="background"], [class], [id]) {
              background-color: transparent !important;
            }
          }
        }
        @-moz-document url("about:blank") {
          @media (prefers-color-scheme: dark) {
            :root {
              background-color: #${config.colorScheme.colors.base02} !important;
            }
          }
        }
      '';

      settings = import ./settings.nix;
    };
  };
}
