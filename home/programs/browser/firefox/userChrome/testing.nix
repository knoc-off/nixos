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
    /* These two come bundled together */
    @import "${firefox-csshacks}/chrome/click_selected_tab_to_focus_urlbar.css";
    @import "${firefox-csshacks}/chrome/selected_tab_as_urlbar.css";

    @import "${firefox-csshacks}/chrome/auto_devtools_theme.css";
    @import "${firefox-csshacks}/chrome/auto_devtools_theme_for_rdm.css";

    @import "${firefox-csshacks}/chrome/button_effect_scale_onhover.css";
    @import "${firefox-csshacks}/chrome/urlbar_connection_type_background_colors.css";
    /*
     * things i find could be interesting
     * dark_checkboxes_and_radios.css
     *
     *
     *
     *
     *
    */


    /* Theme Settings */
  /* Source file https://github.com/MrOtherGuy/firefox-csshacks/tree/master/chrome/color_variable_template.css made available under Mozilla Public License v. 2.0
  See the above repository for updates as well as full license text. */

  /* You should enable any non-default theme for these to apply properly. Built-in dark and light themes should work */
  :root {
    /* Base colors */
    --base00: #${theme.base00};
    --base01: #${theme.base01};
    --base02: #${theme.base02};
    --base07: #${theme.base07};
    --base0B: #${theme.base0B};
    --base0E: #${theme.base0E};

    /* Accent colors */
    --red00: #${theme.red00};
    --orange00: #${theme.orange00};
    --yellow00: #${theme.yellow00};
    --blue00: #${theme.blue00};
    --purple00: #${theme.purple00};
    --cyan00: #${theme.cyan00};
    --gray03: #${theme.gray03};

    /* Popup panels */
    --arrowpanel-background: var(--base02) !important;
    --arrowpanel-border-color: var(--base01) !important;
    --arrowpanel-color: var(--base07) !important;
    --arrowpanel-dimmed: rgba(0,0,0,0.4) !important;

    /* Window and toolbar background */
    --lwt-accent-color: var(--base01) !important;
    --lwt-accent-color-inactive: var(--base02) !important;
    --toolbar-bgcolor: var(--base00) !important;

    /* Tabs with system theme - text is not controlled by variable */
    --tab-selected-bgcolor: var(--base01) !important;

    /* Tabs with any other theme */
    --lwt-text-color: var(--base07) !important;
    --lwt-selected-tab-background-color: var(--base02) !important;

    /* Toolbar area */
    --toolbarbutton-icon-fill: var(--base07) !important;
    --lwt-toolbarbutton-hover-background: var(--base01) !important;
    --lwt-toolbarbutton-active-background: var(--base02) !important;

    /* URL bar */
    --toolbar-field-border-color: var(--base01) !important;
    --toolbar-field-focus-border-color: var(--base03) !important;
    --urlbar-popup-url-color: var(--base03) !important;

    /* URL bar Firefox < 92 */
    --lwt-toolbar-field-background-color: var(--base02) !important;
    --lwt-toolbar-field-focus: var(--gray03) !important;
    --lwt-toolbar-field-color: var(--base07) !important;
    --lwt-toolbar-field-focus-color: var(--base07) !important;

    /* URL bar Firefox 92+ */
    --toolbar-field-background-color: var(--base02) !important;
    --toolbar-field-focus-background-color: var(--gray03) !important;
    --toolbar-field-color: var(--base03) !important;
    --toolbar-field-focus-color: var(--base03) !important;

    /* Sidebar */
    --lwt-sidebar-background-color: var(--base02) !important;
    --lwt-sidebar-text-color: var(--base07) !important;
  }

  /* Line between nav-bar and tabs toolbar, also fallback color for border around selected tab */
  #navigator-toolbox {
    --lwt-tabs-border-color: var(--base03) !important;
  }

  /* Line above tabs */
  #tabbrowser-tabs {
    --lwt-tab-line-color: var(--base03) !important;
  }

  /* The header-area of sidebar needs this to work */
  #sidebar-box {
    --sidebar-background-color: var(--base02) !important;
  }




''
