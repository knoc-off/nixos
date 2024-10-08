{ pkgs, theme, firefox-csshacks, colorLib }:

{ enableSidebarCustomization ? false
, hideTabs ? false
, enableColorScheme ? false
, autohideToolbox ? false
, autohideSidebar ? false
, extraStyles ? ""
, colorSchemeOptions ? {}
}:

let
  sidebarCustomization = import ./userChrome/sidebar.nix { inherit theme colorLib firefox-csshacks; };
  colorScheme = import ./userChrome/colors.nix { inherit theme colorLib; } colorSchemeOptions;

in ''
  ${if autohideToolbox then ''@import "${firefox-csshacks}/chrome/autohide_toolbox.css";'' else ""}
  ${if autohideSidebar then ''@import "${firefox-csshacks}/chrome/autohide_sidebar.css";'' else ""}
  ${if enableSidebarCustomization then sidebarCustomization else ""}
  ${if hideTabs then ''
      /* Hide native tabs (useful with Sidebery extension) */
      #TabsToolbar {
        visibility: collapse;
      }

      /* Hide window controls (minimize, close, etc.) */
      .titlebar-buttonbox-container,
      .titlebar-spacer[type="post-tabs"] {
        display: none;
      }
    '' else ""}
  ${if enableColorScheme then colorScheme else ""}
  ${extraStyles}
''
