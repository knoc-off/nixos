{ theme, colorLib }:
{ enablePopupPanels ? false
, enableWindowAndToolbar ? false
, enableTabs ? false
, enableURLBar ? false
, enableInputFields ? false
, enableDropdowns ? false
, enablePanels ? false
, enableContextMenus ? false
, enableButtons ? false
, enableScrollbars ? false
, enableSelection ? false
, enableTooltips ? false
}:

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

  popupPanels = ''
    /* Popup panels */
    --arrowpanel-background: ${rc 0.2 0.1 pr} !important;
    --arrowpanel-border-color: ${rc 0.1 0.1 pr} !important;
    --arrowpanel-color: ${rc 0.9 0.1 ne} !important;
    --arrowpanel-dimmed: ${rc 0.7 0.1 ne} !important;
  '';

  windowAndToolbar = ''
    /* Window and toolbar background */
    --lwt-accent-color: ${rc 0.2 0.1 pr} !important;
    --lwt-accent-color-inactive: ${rc 0.1 0.1 pr} !important;
    --toolbar-bgcolor: ${rc 0.2 0.1 pr} !important;
  '';

  tabs = ''
    /* Tabs with system theme - text is not controlled by variable */
    --tab-selected-bgcolor: ${rc 0.3 0.1 pr} !important;

    /* Tabs with any other theme */
    --lwt-text-color: ${rc 0.7 0.1 ne} !important;
    --lwt-selected-tab-background-color: ${rc 0.3 0.1 pr} !important;

    /* Toolbar area */
    --toolbarbutton-icon-fill: ${rc 0.9 0.1 ne} !important;
    --lwt-toolbarbutton-hover-background: ${rc 0.9 0.1 ne} !important;
    --lwt-toolbarbutton-active-background: ${rc 0.7 0.1 ne} !important;
  '';

  urlBar = ''
    /* URL bar */
    --toolbar-field-border-color: ${rc 0.5 0.1 ne} !important;
    --toolbar-field-focus-border-color: ${rc 0.7 0.1 ne} !important;
    --urlbar-popup-url-color: ${rc 0.9 0.1 ne} !important;
    --urlbar-popup-action-row-color: ${rc 0.9 0.1 ne} !important;
    --urlbar-popup-subtitle-color: ${rc 0.7 0.1 ne} !important;
    --urlbar-popup-title-color: ${rc 0.5 0.1 ne} !important;
    --urlbar-popup-background: ${rc 0.3 0.1 pr} !important;
  '';

  inputFields = ''
    /* Input fields */
    --input-background: ${rc 0.2 0.1 pr} !important;
    --input-border-color: ${rc 0.5 0.1 ne} !important;
    --input-color: ${rc 0.9 0.1 ne} !important;
  '';

  dropdowns = ''
    /* Dropdowns */
    --dropdown-background: ${rc 0.2 0.1 pr} !important;
    --dropdown-border-color: ${rc 0.5 0.1 ne} !important;
    --dropdown-color: ${rc 0.9 0.1 ne} !important;
  '';

  panels = ''
    /* Panels */
    --panel-background: ${rc 0.2 0.1 pr} !important;
    --panel-border-color: ${rc 0.5 0.1 ne} !important;
    --panel-color: ${rc 0.9 0.1 ne} !important;
  '';

  contextMenus = ''
    /* Context menus */
    --menu-background: ${rc 0.2 0.1 pr} !important;
    --menu-border-color: ${rc 0.5 0.1 ne} !important;
    --menu-color: ${rc 0.9 0.1 ne} !important;
  '';

  buttons = ''
    /* Buttons */
    --button-background: ${rc 0.3 0.1 pr} !important;
    --button-border-color: ${rc 0.5 0.1 ne} !important;
    --button-color: ${rc 0.9 0.1 ne} !important;
  '';

  scrollbars = ''
    /* Scrollbars */
    --scrollbar-color: ${rc 0.5 0.1 ne} ${rc 0.2 0.1 pr} !important;
  '';

  selection = ''
    /* Selection */
    --selection-background: ${rc 0.4 0.1 pr} !important;
    --selection-color: ${rc 0.9 0.1 ne} !important;
  '';

  tooltips = ''
    /* Tooltips */
    --tooltip-background: ${rc 0.2 0.1 pr} !important;
    --tooltip-color: ${rc 0.9 0.1 ne} !important;
  '';

in
''
  /* Color configuration */
  :root {
    -moz-border-radius: 1em;

    ${if enablePopupPanels then popupPanels else ""}
    ${if enableWindowAndToolbar then windowAndToolbar else ""}
    ${if enableTabs then tabs else ""}
    ${if enableURLBar then urlBar else ""}
    ${if enableInputFields then inputFields else ""}
    ${if enableDropdowns then dropdowns else ""}
    ${if enablePanels then panels else ""}
    ${if enableContextMenus then contextMenus else ""}
    ${if enableButtons then buttons else ""}
    ${if enableScrollbars then scrollbars else ""}
    ${if enableSelection then selection else ""}
    ${if enableTooltips then tooltips else ""}
  }
''
