{ theme, pkgs, firefox-csshacks, colorLib }:
let
  ho = colorLib.hexStrToOklch;
  oh = colorLib.oklchToHex;
  sl = value: color: colorLib.oklchmod.setLightness value color;
  sc = value: color: colorLib.oklchmod.setChroma value color;

  pr = theme.primary;
  se = theme.secondary;
  ne = theme.neutral;
  a1 = theme.accent1;
  a2 = theme.accent2;

  # Function to reduce chroma (saturation) and set lightness
  rc = l: c: color: oh (sc c (sl l (ho color)));
in
''
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
    background-color: ${rc 0.3 0.1 pr} !important;
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
    background-color: ${rc 0.3 0.1 pr} !important;
  }

  /* Bookmarks and history panels background color */
  #bookmarksPanel, #history-panel {
    background-color: ${rc 0.2 0.1 pr} !important;
  }

  /* Sidebar color settings */
  #sidebar-header,
  #sidebar-search-container,
  #bookmarks-view-children,
  #historyTree {
    color: ${rc 0.2 0.1 pr} !important;
    background-color: ${rc 0.2 0.1 pr} !important;
    -moz-appearance: none !important;
    border-color: transparent !important;
  }

  /* Search box in the sidebar */
  .sidebar-panel #search-box {
    background-color: ${rc 0.4 0.1 pr} !important;
    color: ${rc 0.9 0.1 ne} !important;
  }

  /* Sidebar and header background settings */
  #sidebar,
  #sidebar-header {
    background-color: ${rc 0.3 0.1 pr} !important;
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
    --arrowpanel-background: ${rc 0.2 0.1 pr} !important;
    --arrowpanel-border-color: ${rc 0.1 0.1 pr} !important;
    --arrowpanel-color: ${rc 0.9 0.1 ne} !important;
    --arrowpanel-dimmed: ${rc 0.7 0.1 ne} !important;

    /* Window and toolbar background */
    --lwt-accent-color: ${rc 0.2 0.1 pr} !important;
    --lwt-accent-color-inactive: ${rc 0.1 0.1 pr} !important;
    --toolbar-bgcolor: ${rc 0.2 0.1 pr} !important;

    /* Tabs with system theme - text is not controlled by variable */
    --tab-selected-bgcolor: ${rc 0.3 0.1 pr} !important;

    /* Tabs with any other theme */
    --lwt-text-color: ${rc 0.7 0.1 ne} !important;
    --lwt-selected-tab-background-color: ${rc 0.3 0.1 pr} !important;

    /* Toolbar area */
    --toolbarbutton-icon-fill: ${rc 0.9 0.1 ne} !important;
    --lwt-toolbarbutton-hover-background: ${rc 0.9 0.1 ne} !important;
    --lwt-toolbarbutton-active-background: ${rc 0.7 0.1 ne} !important;

    /* URL bar */
    --toolbar-field-border-color: ${rc 0.5 0.1 ne} !important;
    --toolbar-field-focus-border-color: ${rc 0.7 0.1 ne} !important;
    --urlbar-popup-url-color: ${rc 0.9 0.1 ne} !important;
    --urlbar-popup-action-row-color: ${rc 0.9 0.1 ne} !important;
    --urlbar-popup-subtitle-color: ${rc 0.7 0.1 ne} !important;
    --urlbar-popup-title-color: ${rc 0.5 0.1 ne} !important;
    --urlbar-popup-background: ${rc 0.3 0.1 pr} !important;

    /* Input fields */
    --input-background: ${rc 0.2 0.1 pr} !important;
    --input-border-color: ${rc 0.5 0.1 ne} !important;
    --input-color: ${rc 0.9 0.1 ne} !important;

    /* Dropdowns */
    --dropdown-background: ${rc 0.2 0.1 pr} !important;
    --dropdown-border-color: ${rc 0.5 0.1 ne} !important;
    --dropdown-color: ${rc 0.9 0.1 ne} !important;

    /* Panels */
    --panel-background: ${rc 0.2 0.1 pr} !important;
    --panel-border-color: ${rc 0.5 0.1 ne} !important;
    --panel-color: ${rc 0.9 0.1 ne} !important;

    /* Context menus */
    --menu-background: ${rc 0.2 0.1 pr} !important;
    --menu-border-color: ${rc 0.5 0.1 ne} !important;
    --menu-color: ${rc 0.9 0.1 ne} !important;

    /* Buttons */
    --button-background: ${rc 0.3 0.1 pr} !important;
    --button-border-color: ${rc 0.5 0.1 ne} !important;
    --button-color: ${rc 0.9 0.1 ne} !important;

    /* Scrollbars */
    --scrollbar-color: ${rc 0.5 0.1 ne} ${rc 0.2 0.1 pr} !important;

    /* Selection */
    --selection-background: ${rc 0.4 0.1 pr} !important;
    --selection-color: ${rc 0.9 0.1 ne} !important;

    /* Tooltips */
    --tooltip-background: ${rc 0.2 0.1 pr} !important;
    --tooltip-color: ${rc 0.9 0.1 ne} !important;
  }
''
