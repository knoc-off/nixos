{ inputs, math, pkgs, theme, lib, color-lib, config, ... }:
let
  addons = inputs.firefox-addons.packages.${pkgs.system};

  firefox-csshacks = pkgs.stdenv.mkDerivation {
    name = "patched-firefox-csshacks";
    src = inputs.firefox-csshacks;
    installPhase = ''
      cp -r . $out
    '';
  };

in rec {

  home.sessionVariables = { BROWSER = "firefox"; };

  programs.firefox = {
    enable = true;
    profiles = {
      "main" = {
        isDefault = true;
        id = 0;
        name = "main";

        # Extensions for the main profile
        extensions.packages = with addons; [
          # Essential
          ublock-origin
          bitwarden
          sidebery
          tridactyl
          # Privacy
          smart-referer
          cookie-autodelete
          user-agent-string-switcher
        ];

        userContent = ''
          /* Firefox profile directory/chrome/userContent.css */
          /* Apply to all about: pages, including about:home and about:newtab */
          @-moz-document url-prefix("about:") {
            #root,
            .newtab-main,
            .outer-wrapper {
              background-color: #${theme.base00} !important;  /* Dark background color */
              color: #${theme.base07} !important;             /* Text color */
            }

            /* Optional: Remove background images from new tab page */
            .wallpaper-input[style*="background-image"] {
              background-image: none !important;
            }
          }
        '';

        userChrome =
          import ./userChrome.nix { inherit theme color-lib firefox-csshacks; };
        search = import ./searchEngines { inherit pkgs lib; };
      };

      "minimal" = {
        isDefault = false;
        id = 1;
        name = "minimal";

        # Extensions for the minimal profile
        extensions.packages = with addons; [
          # Essential
          ublock-origin
          bitwarden
          sidebery
          tridactyl
        ];

        # Rest of minimal profile config...
        search = import ./searchEngines { inherit pkgs lib; };
      };

      "testing2" = {
        isDefault = false;
        id = 2;
        name = "testing2";

        settings =
          import ./settings/default.nix { inherit theme math lib color-lib; };
        extensions.packages = with addons; [ sidebery ];
        userChrome = import ./userChrome-minimal.nix {
          inherit theme color-lib firefox-csshacks;
        };
      };

      "projection" = {
        isDefault = false;
        id = 3;
        name = "projection";

        settings =
          import ./settings/default.nix { inherit theme math lib color-lib; };
        extensions.packages = with addons; [ sidebery ];
        userChrome = import ./userChrome-minimal.nix {
          inherit theme color-lib firefox-csshacks;
        };
      };
    };
  };

  # auto generate the desktop entries for each profile
  xdg.desktopEntries = let
    mkFirefoxDesktopEntry = profile: {
      name = "Firefox (${profile.name})";
      genericName = "Web Browser";
      exec = "${pkgs.firefox}/bin/firefox -P ${profile.name}";
      icon =
        "${pkgs.firefox}/lib/firefox/browser/chrome/icons/default/default128.png";
      type = "Application";
      categories = [ "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
  in lib.mapAttrs (name: profile: mkFirefoxDesktopEntry profile)
  programs.firefox.profiles

  //

  {
    firefox-private = {
      name = "Firefox Private";
      genericName = "Web Browser";
      exec = "${pkgs.firefox}/bin/firefox --private-window";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      type = "Application";
      categories = [ "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
  };

}
