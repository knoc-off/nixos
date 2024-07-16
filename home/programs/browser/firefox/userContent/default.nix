{theme}: ''
  .tabbrowser-tabbox {
      background-color: #${theme.base02} !important;
  }

  @-moz-document plain-text-document(), media-document(all) {
    @media (prefers-color-scheme: dark) {
      :root {
        background-color: #${theme.base02} !important;
        foreground-color: #${theme.base07} !important;
      }
      body:not([style*="background"], [class], [id]) {
        background-color: transparent !important;
      }
    }
  }

  /* remove flash */
  @-moz-document url("about:home"),url("about:blank"),url("about:newtab"),url("about:privatebrowsing"){
    body{background-color: #${theme.base02} !important }
  }

  @-moz-document url("about:preferences#home"){
    body{background-color: #${theme.base02} !important }
  }

  /* ~~~~~~~~~~~~~~~~~~~~~~~
  /* Color Configs */
  /* not sure how i feel about this, because its hard to tell what is what */
  /* and themes can have unintended effects. */
  /* need to document the effects.*/
  :root {
    /* this effects text color in firefox menus. */
    --in-content-page-color: #${theme.white00} !important;
    --in-content-page-background: #${theme.base00} !important;
    --in-content-text-color: #${theme.white02} !important;
    --in-content-selected-text: #${theme.white01} !important;
    --in-content-box-background: #${theme.base00} !important;
    --in-content-box-background-odd: #${theme.base00} !important;
    --in-content-box-background-hover: #${theme.base01} !important;
    --in-content-box-background-active: #${theme.base01} !important;
    --in-content-box-border-color: #${theme.cyan00} !important;
    --in-content-item-hover: #${theme.base01} !important;
    --in-content-item-selected: #${theme.base01} !important;
    --in-content-border-highlight: #${theme.cyan00} !important;
    --in-content-border-focus: #${theme.cyan00} !important;
    --in-content-border-hover: #${theme.cyan00} !important;
    --in-content-border-active: #${theme.cyan00} !important;
    --in-content-border-active-shadow: transparent !important;
    --in-content-border-invalid: #${theme.red00} !important;
    --in-content-border-invalid-shadow: #${theme.red02};
    --in-content-border-color: #${theme.cyan02} !important;
    --in-content-category-outline-focus: 1px dotted #${theme.cyan00} !important;
    --in-content-category-text-selected: #${theme.cyan00} !important;
    --in-content-category-text-selected-active: #${theme.cyan00} !important;
    --in-content-category-background-hover: #${theme.base00} !important;
    --in-content-category-background-active: #${theme.base00} !important;
    --in-content-category-background-selected-hover: #${theme.base00} !important;
    --in-content-category-background-selected-active: #${theme.base00} !important;
    --in-content-tab-color: #${theme.yellow00} !important;
    --in-content-link-color: #${theme.cyan02} !important;
    --in-content-link-color-hover: #${theme.cyan00} !important;
    --in-content-link-color-active: #${theme.cyan00} !important;
    --in-content-link-color-visited: #${theme.yellow00} !important;
    --in-content-button-background: var(--grey-90-a10);
    --in-content-button-background-hover: var(--grey-90-a20);
    --in-content-button-background-active: var(--grey-90-a30);
    --in-content-primary-button-background: var(--blue-60);
    --in-content-primary-button-background-hover: var(--blue-70);
    --in-content-primary-button-background-active: var(--blue-80);
    --in-content-table-background: transparent !important;
    --in-content-table-border-dark-color: #${theme.cyan02};
    --in-content-table-header-background: #${theme.blue01};
    --blue-40: #${theme.blue00};
    --blue-40-a10: rgb(69, 161, 255, 0.1);
    --blue-50: #${theme.blue01};
    --blue-50-a30: rgba(10, 132, 255, 0.3);
    --blue-60: #${theme.blue02} !important;
    --blue-70: #${theme.blue03} !important;
    --blue-80: #${theme.blue04} !important;
    --grey-20: #${theme.base01} !important; /* bg color 2 - ish*/
    --grey-30: #${theme.gray01} !important; /* text highlight color? */
    --grey-60: #${theme.gray03} !important;
    --grey-90: #${theme.gray04} !important; /* background bar, inspect menu */
    --grey-90-a10: #${theme.gray03} !important; /* drop shadow? */
    --grey-90-a20: #${theme.gray04} !important;
    --grey-90-a30: #${theme.gray05} !important;
    --grey-90-a40: #${theme.gray06} !important;
    --grey-90-a50: #${theme.gray06} !important;
    --red-50: #${theme.red00} !important;
    --red-50-a30: #${theme.red01} !important;
    --red-60: #${theme.red02} !important;
    --yellow-50: #${theme.yellow00} !important;
    --yellow-90: #${theme.yellow04} !important;
    --shadow-10: 0 1px 4px var(--grey-90-a10);
    --card-padding: 16px;
    --card-shadow: var(--shadow-10);
    --card-outline-color: var(--grey-30);
    --card-shadow-hover: var(--card-shadow), 0 0 0 5px var(--card-outline-color);
    --card-shadow-focus: 0 0 0 2px var(--blue-50), 0 0 0 6px var(--blue-50-a30);
  }

  :root{
    -moz-border-radius: 1em;
    /* Popup panels */
    --arrowpanel-background: #${theme.base01} !important;
    --arrowpanel-border-color: #${theme.base00} !important;
    --arrowpanel-color: #${theme.base06} !important;
    --arrowpanel-dimmed: #${theme.base05} !important;

    /* window and toolbar background */
    --lwt-accent-color: #${theme.base01} !important;
    --lwt-accent-color-inactive: #${theme.base00} !important;
    --toolbar-bgcolor: #${theme.base01} !important;

    /* tabs with system theme - text is not controlled by variable */
    --tab-selected-bgcolor: #${theme.base02} !important;

    /* tabs with any other theme */
    --lwt-text-color: #${theme.base05} !important;
    --lwt-selected-tab-background-color: #${theme.base02} !important;

    /* toolbar area */
    --toolbarbutton-icon-fill: #${theme.base06} !important;
    --lwt-toolbarbutton-hover-background: #${theme.base06} !important;
    --lwt-toolbarbutton-active-background: #${theme.base05} !important;

    /* urlbar */
    --toolbar-field-border-color: #${theme.base04} !important;
    --toolbar-field-focus-border-color: #${theme.base05} !important;
    --urlbar-popup-url-color: #${theme.base06} !important;

    /* urlbar Firefox < 92 */
    --lwt-toolbar-field-background-color: #${theme.base02} !important;
    --lwt-toolbar-field-focus: #${theme.base07} !important;
    --lwt-toolbar-field-color: #${theme.base06} !important;
    --lwt-toolbar-field-focus-color: #${theme.base07} !important;

    /* urlbar Firefox 92+ */
    --toolbar-field-background-color: #${theme.base02} !important;
    --toolbar-field-focus-background-color: #${theme.base03} !important;
    --toolbar-field-color: #${theme.base06} !important;
    --toolbar-field-focus-color: #${theme.base07} !important;

    /* sidebar - note the sidebar-box rule for the header-area */
    --lwt-sidebar-background-color: #${theme.base02} !important;
    --lwt-sidebar-text-color: #${theme.base06} !important;
  }
   ~~~~~~~~~~~~ */

''
