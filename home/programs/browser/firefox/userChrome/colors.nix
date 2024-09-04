{ theme }:
''
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
