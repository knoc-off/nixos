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
  };
  # TODO:
  # The css hacks should be automated. this is not ideal.
  # then we can do compile time checks if the file exists, etc.
  # idea:
  #   { chrome.autohide_sidebar.enable = true }
  #     - could also provide patches to apply per file. etc.
  # OR:
  #   chrome = [ autohide_sidebar autohide_bookmarks_toolbar auto_devtools_theme_for_rdm ...]
  #     - less flexible?
  #     - unless, we make each a file. IE:
  #       chrome with (function-to-extract-as-files); = [ (autohide file_modifications) autohide_2]
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

  /* Hide native tabs (useful with Sidebery extension) */
  #TabsToolbar {
    visibility: collapse;
  }

  /* Hide window controls (minimize, close, etc.) */
  .titlebar-buttonbox-container,
  .titlebar-spacer[type="post-tabs"] {
    display: none;
  }

''
