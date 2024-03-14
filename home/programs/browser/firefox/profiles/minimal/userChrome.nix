{ theme, pkgs }:
let
  firefox-csshacks = pkgs.fetchFromGitHub {
    owner = "MrOtherGuy";
    repo = "firefox-csshacks";
    rev = "67a9e9f9c96e6d007b4c57f1dd7eaceaee135178";
    sha256 = "sha256-uz6tqkjjTFMvY6IY70ke8dW5nst0AJoWJHObtzalQAc=";
  };
in
''
  @import "${firefox-csshacks}/chrome/autohide_sidebar.css";
  /*@import "./firefox-csshacks/chrome/autohide_bookmarks_and_main_toolbars.css";*/


  /* override sidebar options */
  /* https://pastebin.com/KFHjwR4d */
  #sidebar-box{
    --uc-autohide-sidebar-delay: 100ms;
    --uc-autohide-transition-duration: 215ms;
    --uc-sidebar-width: var(--sidebar-width);
    --uc-sidebar-hover-width: 25vw;
    --uc-autohide-transition-type: ease-in-out;

    background-color: #${theme.base02} !important;
  }

  /* this is url bar options */
  :root {
      --sidebar-width: 40px;
      --panel-width: 100vw; /* url bar width */
      --panel-hide-offset: -30px;
      --opacity-when-hidden: 0.0;
  }

  /* this removes the sidebar header */
  #sidebar-header {
      display: none
  }

  /* not sure. i think it removes the url bar */
  * {
    background-color: #${theme.hp} !important;
    -moz-appearance: none !important;
  }

  /* TODO: what does this do. */
  .tabbrowser-tabpanels {
      background-color: #${theme.base02} !important;
  }
  browser {
      background-color: #${theme.base02} !important;
  }

  /* TODO: what does this do. */
  #bookmarksPanel, #history-panel {
    background-color: #${theme.base01} !important;
  }

  /* sets the color of the sidebar */
  #sidebar-header,#sidebar-search-container,#bookmarks-view-children,#historyTree {
    color: #${theme.base01} !important;
    background-color: #${theme.base01} !important;
    -moz-appearance:none !important;
    border-color:transparent !important;
  }


  /* TODO: what does this do. */
  .sidebar-panel #search-box{
    background-color: #${theme.base03} !important;
    color: #${theme.base06} !important;
  }

  /* TODO: what does this do. */
  #sidebar,
  #sidebar-header {
    background-color: #${theme.base02} !important;
    border-bottom: none !important;
    background-image: var(--lwt-additional-images);
    background-position: auto;
    background-size: auto;
    background-repeat: no-repeat;
  }

  /* TODO: what does this do. */
  /*
  #browser {
    --sidebar-border-color: #${theme.base01} !important;
  }
  #sidebar-header::before {
    background-color: #${theme.base02} !important;
  }

  #sidebar-header::after{
    background-color: #${theme.base02} !important;
  }
  */

  /* hides the native tabs */
  /* to be used together with sideberry. */
  /* there is a way to auto collapse/ expand when sideberry is not displaying tabs*/
  #TabsToolbar {
    visibility: collapse;
  }

  /* Hide window controls, minimise, close, etc. */
  .titlebar-buttonbox-container{
    display:none
  }
  .titlebar-spacer[type="post-tabs"]{
    display:none
  }


  /* Color Configs */
  /* TODO: should try to remove &/or debug */
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

  /* line between nav-bar and tabs toolbar,
  also fallback color for border around selected tab */
  #navigator-toolbox{ --lwt-tabs-border-color: #${theme.base02} !important; }

  /* Line above tabs */
  #tabbrowser-tabs{ --lwt-tab-line-color: #${theme.base05} !important; }

  /* the header-area of sidebar needs this to work */
  #sidebar-box{ --sidebar-background-color: #${theme.base00} !important; }

  /* remove flash of loading screen, TODO: (?), Implement Fade to white. */
  /* This changes the color of the loading page */
  #tabbrowser-tabpanels,
  #webextpanels-window,
  #webext-panels-stack,
  #webext-panels-browser {
    background: #${theme.base02} !important;
  }

  /* Auto-hide address bar */
  #navigator-toolbox{
    position: fixed !important;
    /* Comment out following line to get 'slide-page-down' reveal, like in F11 fullscreen mode */
    display: block;
    transition: margin-top 82ms 33ms linear, opacity 82ms 33ms linear !important;
    z-index: 1;
    opacity: 1;
    /* Spacing on the left for sidebar */
    margin-left: var(--sidebar-width);
    /* Disabled the borders, as the bottom one seemed to have unwanted top padding sometimes */
    border: none !important;
  }

  /* This makes the urlbar / address bar not reach the full width of the screen */
  #navigator-toolbox,
  #navigator-toolbox > *{
    /* calculate pannel width minus --uc-sidebar-width */
    width: calc(var(--panel-width) - var(--sidebar-width));
  }


  /* TODO: Some unintended effects, when bookmarks toolbar is expanded*/
  /* if the cursor is at the top 30px of the screen, show the toolbar */
  /* and if the cursor is at the left half of the screen show the toolbar */
  #navigator-toolbox:not(:focus-within):not(:hover){
    margin-top: var(--panel-hide-offset);
    /* Hide the toolbar when not hovered */
    opacity: var(--opacity-when-hidden);
  }


  /* Disable auto-hiding when in 'customize' mode */
  :root[customizing] #navigator-toolbox{
    position: relative !important;
    opacity: 1 !important;
    margin-top: 0px;
  }



  /* TODO: Document this or remove */
  /* :root[tabsintitlebar] { */
  /*  appearance: -moz-win-glass !important; */
  /* } */

''
