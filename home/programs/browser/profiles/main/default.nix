{ pkgs, config, inputs, lib, ... }:
let
  # unsigned int
  id = 0;

  # computers name
  profileName = "${config.home.username}-${toString id}";

  # Your firefox install path
  firefoxPath = ".mozilla/firefox";

  # The location of your firefox config
  profilePath = "${firefoxPath}/${profileName}";

  # Firefox Addons, may want to change this at some point
  addons = inputs.firefox-addons.packages.${pkgs.system};

  # Edge modifications, drawer, style, etc.
  Edge-Mimicry = pkgs.fetchFromGitHub {
    owner = "UnlimitedAvailableUsername";
    repo = "Edge-Mimicry-Tree-Style-Tab-For-Firefox";
    rev = "f9c59082c4803aace8c07fe9888b0216e9e680a7";
    sha256 = "sha256-dEaWqwbui70kCzBeNjJIttKSSgi4rAncc8tGcpGvpl4=";
  };

in
{

  home.file = {
    # Could think about putting this back one dir, to be reused
    "themes" = {
      source = "${Edge-Mimicry}";
      target = "${profilePath}/chrome/themes";
    };
  };

  #home.file."${profilePath}/chrome/sidebar-mods.css".text ;
  #home.file."${profilePath}/chrome/treestyletab-edge-mimicry.css".text ;
  #  home.file."${profilePath}/chrome/sidebar-mods.css".text = builtins.readFile
  #    (builtins.fetchurl {
  #      url =
  #        "https://raw.githubusercontent.com/UnlimitedAvailableUsername/Edge-Mimicry-Tree-Style-Tab-For-Firefox/main/edge-mimicry/sidebar-mods.css";
  #      sha256 = "100xnrf8hzlhl88i8q2s8bva5amykd0dcbl08x9xigrl1yplcl5y";
  #    });
  #
  #  home.file."${profilePath}/chrome/treestyletab-edge-mimicry.css".text =
  #    builtins.readFile (builtins.fetchurl {
  #      url =
  #        "https://raw.githubusercontent.com/UnlimitedAvailableUsername/Edge-Mimicry-Tree-Style-Tab-For-Firefox/main/treestyletab-edge-mimicry.css";
  #      sha256 = "17dpnmdkvj1y56w12yb4bc0g0ryyyjbd9jnbsw33bn0030qp4594";
  #    });

  programs.firefox = {
    profiles.${profileName} = {
      isDefault = false;
      inherit id;
      name = "${profileName}";

      extensions = with addons; [
        # Privacy and Security
        ublock-origin
        addy_io
        clearurls
        #privacy-possum
        #decentraleyes
        darkreader
        #sponsorblock
        #i-dont-care-about-cookies
        #consent-o-matic

        bitwarden
        canvasblocker
        cookie-autodelete

        # Productivity
        violentmonkey
        tree-style-tab
        smart-referer
        #user-agent-string-switcher
        #single-file
        nighttab
        translate-web-pages

        # Steam-related packages
        # augmented-steam
        # protondb-for-steam
        # steam-database

        # Github-related packages
        #enhanced-github
        #lovely-forks
      ];

      # @import "sidebar-mods.css";
      userChrome = ''
        @import "./themes/edge-mimicry/sidebar-mods.css";

        #sidebar-header {
          display: none;
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
      '';
      userContent = ''
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
