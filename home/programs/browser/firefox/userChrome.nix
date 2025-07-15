{
  theme,
  firefox-csshacks,
  color-lib,
}: let
  sidebar = {
    width = "38px";
    expanded-width = "25vw";
    hide-delay = "100ms";
    animation-duration = "200ms";
    transition-type = "ease-in-out";

    background-color = "#${theme.base00}";
  };
in ''
  /* Import necessary CSS hacks */
  @import "${firefox-csshacks}/chrome/autohide_sidebar.css";
  @import "${firefox-csshacks}/chrome/autohide_bookmarks_toolbar.css";
  @import "${firefox-csshacks}/chrome/auto_devtools_theme_for_rdm.css";

  @import "${firefox-csshacks}/chrome/hide_tabs_toolbar_v2.css";
  /*
  @import "${firefox-csshacks}/chrome/page_action_buttons_on_urlbar_hover.css";
  @import "${firefox-csshacks}/chrome/autohide_toolbox.css";
  */
  /* Sidebar customization */
  #sidebar-box {
    min-width: var(--uc-sidebar-width) !important;
    --uc-autohide-sidebar-delay: ${sidebar.hide-delay} !important;
    --uc-autohide-transition-duration: ${sidebar.animation-duration} !important;
    --uc-sidebar-width: ${sidebar.width} !important;
    --uc-sidebar-hover-width: ${sidebar.expanded-width} !important;
    --uc-autohide-transition-type: ${sidebar.transition-type} !important;
    background-color: ${sidebar.background-color} !important;
    z-index: 3 !important;
  }

  /* URL bar and panel options */
  :root {
    --panel-width: 100vw;
    --panel-hide-offset: -30px;
    --opacity-when-hidden: 0.0;
  }

  /* Remove the sidebar header */
  #sidebar-header {
    display: none;
  }

  /* Tab browser panels background color */
  .tabbrowser-tabpanels, browser {
    background-color: #${theme.base00} !important;
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
    color: #${theme.base05} !important;
    background-color: #${theme.base01} !important;
    -moz-appearance: none !important;
    border-color: transparent !important;
  }

  /* Search box in the sidebar */
  .sidebar-panel #search-box {
    background-color: #${theme.base02} !important;
    color: #${theme.base05} !important;
  }

  /* Sidebar and header background settings */
  #sidebar,
  #sidebar-header {
    background-color: #${theme.base01} !important;
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

  :root{
    /* Popup panels */
    --arrowpanel-background: #${theme.base01} !important;
    --arrowpanel-border-color: #${theme.base03} !important;
    --arrowpanel-color: #${theme.base05} !important;
    --arrowpanel-dimmed: #${theme.base00} !important;
    /* window and toolbar background */
    --lwt-accent-color: #${theme.base02} !important;
    --lwt-accent-color-inactive: #${theme.base01} !important;
    --toolbar-bgcolor: #${theme.base00} !important;
    /* tabs with system theme - text is not controlled by variable */
    --tab-selected-bgcolor: #${theme.base02} !important;
    /* tabs with any other theme */
    --lwt-text-color: #${theme.base05} !important;
    --lwt-selected-tab-background-color: #${theme.base03} !important;
    /* toolbar area */
    --toolbarbutton-icon-fill: #${theme.base05} !important;
    --lwt-toolbarbutton-hover-background: #${theme.base03} !important;
    --lwt-toolbarbutton-active-background: #${theme.base04} !important;
    /* urlbar */
    --toolbar-field-border-color: #${theme.base03} !important;
    --toolbar-field-focus-border-color: #${theme.base0D} !important;
    --urlbar-popup-url-color: #${theme.base0D} !important;
    /* urlbar Firefox < 92 */
    --lwt-toolbar-field-background-color: #${theme.base00} !important;
    --lwt-toolbar-field-focus: #${theme.base01} !important;
    --lwt-toolbar-field-color: #${theme.base05} !important;
    --lwt-toolbar-field-focus-color: #${theme.base06} !important;
    /* urlbar Firefox 92+ */
    --toolbar-field-background-color: #${theme.base00} !important;
    --toolbar-field-focus-background-color: #${theme.base01} !important;
    --toolbar-field-color: #${theme.base05} !important;
    --toolbar-field-focus-color: #${theme.base06} !important;
    /* sidebar - note the sidebar-box rule for the header-area */
    --lwt-sidebar-background-color: #${theme.base01} !important;
    --lwt-sidebar-text-color: #${theme.base05} !important;
  }
  /* line between nav-bar and tabs toolbar, also fallback color for border around selected tab */
  #navigator-toolbox{ --lwt-tabs-border-color: #${theme.base03} !important; }
  /* Line above tabs */
  #tabbrowser-tabs{ --lwt-tab-line-color: #${theme.base0D} !important; }
  /* the header-area of sidebar needs this to work */
  #sidebar-box{ --sidebar-background-color: #${theme.base00} !important; }


''
