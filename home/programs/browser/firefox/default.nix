{ inputs, pkgs, theme, lib, colorLib, config, ... }:
let
  addons = inputs.firefox-addons.packages.${pkgs.system};

  firefox-csshacks = pkgs.stdenv.mkDerivation {
    name = "patched-firefox-csshacks";
    src = inputs.firefox-csshacks;
    installPhase = ''
      cp -r . $out
    '';
  };

  # Extension groups
  essentialExtensions = with addons; [
    ublock-origin
    bitwarden
    sidebery
    tridactyl
  ];

  privacyExtensions = with addons; [
    smart-referer
    cookie-autodelete
    user-agent-string-switcher
  ];

  appearanceExtensions = with addons; [ darkreader nighttab ];

  utilityExtensions = with addons; [
    translate-web-pages
    export-cookies-txt
    violentmonkey
    history-cleaner
    istilldontcareaboutcookies
  ];

  # Combine extension sets with priorities
  mkExtensionSet = sets:
    lib.mkMerge (map (set: lib.mkOverride set.priority set.extensions) sets);

in rec {
  programs.firefox = {
    enable = true;
    profiles."main" = {
      isDefault = true;
      id = 0;
      name = "main";

      # Full featured profile - all extension sets
      extensions = mkExtensionSet [
        {
          priority = 100;
          extensions = essentialExtensions;
        }
        {
          priority = 200;
          extensions = privacyExtensions;
        }
      ];

      userChrome = import ./userChrome.nix { inherit theme colorLib firefox-csshacks; };
      search = import ./searchEngines { inherit pkgs lib; };
    };

    profiles."minimal" = {
      isDefault = false;
      id = 1;
      name = "minimal";

      # Minimal profile - only essential extensions
      extensions = mkExtensionSet [{
        priority = 100;
        extensions = essentialExtensions;
      }];

      # Rest of minimal profile config...
      search = import ./searchEngines { inherit pkgs lib; };
    };

    profiles."testing2" = {
      isDefault = false;
      id = 2;
      name = "testing2";

    };
  };

  # auto generate the desktop entries for each profile
  xdg.desktopEntries = let
    mkFirefoxDesktopEntry = profile: {
      name = "Firefox (${profile.name})";
      comment = "Web Browser";
      exec = "${pkgs.firefox}/bin/firefox --profile ${profile.name}";
      icon =
        "${pkgs.firefox}/lib/firefox/browser/chrome/icons/default/default128.png";
      categories = [ "Application" "Network" "WebBrowser" ];
    };
  in lib.mapAttrs (name: profile: mkFirefoxDesktopEntry profile)
  programs.firefox.profiles // {
    firefox-private = {
      name = "firefox private";
      genericName = "Web Browser";
      exec = "firefox --private-window %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = [ "Application" "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
  };
}
