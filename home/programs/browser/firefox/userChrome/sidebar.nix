{ theme, firefox-csshacks }:
''
  /* Sidebar customization */
  #sidebar-box {
    --uc-autohide-sidebar-delay: 100ms;
    --uc-autohide-transition-duration: 215ms;
    --uc-sidebar-width: var(--sidebar-width);
    --uc-sidebar-hover-width: 25vw;
    --uc-autohide-transition-type: ease-in-out;
    background-color: #${theme.base02} !important;
    foreground-color: #${theme.white00} !important;
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

  /* Sidebar color settings */
  #sidebar-header,
  #sidebar-search-container,
  #bookmarks-view-children,
  #historyTree {
    color: #${theme.white00} !important;
    background-color: #${theme.base01} !important;
    foreground-color: #${theme.white00} !important;
    -moz-appearance: none !important;
    border-color: transparent !important;
  }

  /* Search box in the sidebar */
  .sidebar-panel #search-box {
    background-color: #${theme.base03} !important;
    foreground-color: #${theme.white00} !important;
    color: #${theme.white00} !important;
  }

  /* Sidebar and header background settings */
  #sidebar,
  #sidebar-header {
    background-color: #${theme.base02} !important;
    foreground-color: #${theme.white00} !important;
    color: #${theme.white00} !important;
    border-bottom: none !important;
    background-image: var(--lwt-additional-images);
    background-position: auto;
    background-size: auto;
    background-repeat: no-repeat;
  }
''
