{ pkgs, theme }:

{ enableSidebarCustomization ? false
, enableTabsCustomization ? false
, enableColorScheme ? false
, enableAutohideFeatures ? false
, extraStyles ? ""
}:

let
  firefox-csshacks = pkgs.fetchFromGitHub {
    owner = "MrOtherGuy";
    repo = "firefox-csshacks";
    rev = "31cb27a5d8e11a4f35499ea9d75cc9939399d915";
    sha256 = "sha256-ALLqHSEk4oC0/KsALYmQyXg4GtxYiOy4bquLjC+dhng=";
  };

  sidebarCustomization = import ./userChrome/sidebar.nix { inherit theme; };
  tabsCustomization = import ./userChrome/tabs.nix;
  colorScheme = import ./userChrome/colors.nix { inherit theme; };
  autohideFeatures = import ./userChrome/autohide.nix { inherit firefox-csshacks; };

in ''
  ${if enableAutohideFeatures then autohideFeatures else ""}
  ${if enableSidebarCustomization then sidebarCustomization else ""}
  ${if enableTabsCustomization then tabsCustomization else ""}
  ${if enableColorScheme then colorScheme else ""}
  ${extraStyles}
''
