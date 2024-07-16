{
  theme,
  pkgs,
}: let
  firefox-csshacks = pkgs.fetchFromGitHub {
    owner = "MrOtherGuy";
    repo = "firefox-csshacks";
    rev = "31cb27a5d8e11a4f35499ea9d75cc9939399d915";
    sha256 = "sha256-ALLqHSEk4oC0/KsALYmQyXg4GtxYiOy4bquLjC+dhng=";
  };
in ''
  /* Import necessary CSS hacks */
  @import "${firefox-csshacks}/chrome/autohide_sidebar.css";
  @import "${firefox-csshacks}/chrome/autohide_toolbox.css";

  /* Sidebar customization */
  #sidebar-box {
    --uc-autohide-sidebar-delay: 100ms;
    --uc-autohide-transition-duration: 215ms;
    --uc-sidebar-width: var(--sidebar-width);
    --uc-sidebar-hover-width: 25vw;
    --uc-autohide-transition-type: ease-in-out;
    background-color: #${theme.base02} !important;
  }

  /* URL bar and panel options */
  :root {
    --sidebar-width: 40px;
    --panel-width: 100vw; /* URL bar width */
    --panel-hide-offset: -30px;
    --opacity-when-hidden: 0.0;
  }

  /* Remove the sidebar header */
  #sidebar-header {
    display: none;
  }

  /* Tab browser panels background color */
  .tabbrowser-tabpanels, browser {
    background-color: #${theme.base02} !important;
  }

  /* Bookmarks and history panels background color */
  #bookmarksPanel, #history-panel {
    background-color: #${theme.base01} !important;
  }

  /* Sidebar color settings */
  #sidebar-header,
  #sidebar-search-container,
  #bookmarks-view-children,
  #historyTree {
    color: #${theme.base01} !important;
    background-color: #${theme.base01} !important;
    -moz-appearance: none !important;
    border-color: transparent !important;
  }

  /* Search box in the sidebar */
  .sidebar-panel #search-box {
    background-color: #${theme.base03} !important;
    color: #${theme.base06} !important;
  }

  /* Sidebar and header background settings */
  #sidebar,
  #sidebar-header {
    background-color: #${theme.base02} !important;
    border-bottom: none !important;
    background-image: var(--lwt-additional-images);
    background-position: auto;
    background-size: auto;
    background-repeat: no-repeat;
  }

  /* Hide native tabs (useful with Sidebery extension) */
  #TabsToolbar {
    visibility: collapse;
  }

  /* Hide window controls (minimize, close, etc.) */
  .titlebar-buttonbox-container,
  .titlebar-spacer[type="post-tabs"] {
    display: none;
  }

  /* Color configuration */
  :root {
    -moz-border-radius: 1em;

    /* Popup panels */
    --arrowpanel-background: #${theme.base01} !important;
    --arrowpanel-border-color: #${theme.base00} !important;
    --arrowpanel-color: #${theme.base06} !important;
    --arrowpanel-dimmed: #${theme.base05} !important;

    /* Window and toolbar background */
    --lwt-accent-color: #${theme.base01} !important;
    --lwt-accent-color-inactive: #${theme.base00} !important;
    --toolbar-bgcolor: #${theme.base01} !important;

    /* Tabs with system theme - text is not controlled by variable */
    --tab-selected-bgcolor: #${theme.base02} !important;

    /* Tabs with any other theme */
    --lwt-text-color: #${theme.base05} !important;
    --lwt-selected-tab-background-color: #${theme.base02} !important;

    /* Toolbar area */
    --toolbarbutton-icon-fill: #${theme.base06} !important;
    --lwt-toolbarbutton-hover-background: #${theme.base06} !important;
    --lwt-toolbarbutton-active-background: #${theme.base05} !important;

    /* URL bar */
    --toolbar-field-border-color: #${theme.base04} !important;
    --toolbar-field-focus-border-color: #${theme.base05} !important;
    --urlbar-popup-url-color: #${theme.base06} !important;
    --urlbar-popup-action-row-color: #${theme.base06} !important;
    --urlbar-popup-subtitle-color: #${theme.base05} !important;
    --urlbar-popup-title-color: #${theme.base04} !important;
    --urlbar-popup-background: #${theme.base02} !important;

    /* Input fields */
    --input-background: #${theme.base01} !important;
    --input-border-color: #${theme.base04} !important;
    --input-color: #${theme.base06} !important;

    /* Dropdowns */
    --dropdown-background: #${theme.base01} !important;
    --dropdown-border-color: #${theme.base04} !important;
    --dropdown-color: #${theme.base06} !important;

    /* Panels */
    --panel-background: #${theme.base01} !important;
    --panel-border-color: #${theme.base04} !important;
    --panel-color: #${theme.base06} !important;

    /* Context menus */
    --menu-background: #${theme.base01} !important;
    --menu-border-color: #${theme.base04} !important;
    --menu-color: #${theme.base06} !important;

    /* Buttons */
    --button-background: #${theme.base02} !important;
    --button-border-color: #${theme.base04} !important;
    --button-color: #${theme.base06} !important;

    /* Scrollbars */
    --scrollbar-color: #${theme.base04} #${theme.base01} !important;

    /* Selection */
    --selection-background: #${theme.base03} !important;
    --selection-color: #${theme.base06} !important;

    /* Tooltips */
    --tooltip-background: #${theme.base01} !important;
    --tooltip-color: #${theme.base06} !important;
  }
''
