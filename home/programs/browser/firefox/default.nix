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
    profiles."main" = {
      isDefault = true;
      id = 0;
      name = "main";

      # Extensions for the main profile
      extensions = with addons; [
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
        @-moz-document url-prefix("about:home") {
          #root,
          .newtab-main,
          .outer-wrapper {
            background-color: #${theme.base00} !important;  /* Dark background color */
            color: #${theme.base07} !important;             /* Text color */
          }

          /* Optional: Remove background images */
          .wallpaper-input[style*="background-image"] {
            background-image: none !important;
          }
        }
      '';

      userChrome =
        import ./userChrome.nix { inherit theme color-lib firefox-csshacks; };
      search = import ./searchEngines { inherit pkgs lib; };
    };

    profiles."minimal" = {
      isDefault = false;
      id = 1;
      name = "minimal";

      # Extensions for the minimal profile
      extensions = with addons; [
        # Essential
        ublock-origin
        bitwarden
        sidebery
        tridactyl
      ];

      # Rest of minimal profile config...
      search = import ./searchEngines { inherit pkgs lib; };
    };

    profiles."testing2" = {
      isDefault = false;
      id = 2;
      name = "testing2";

      settings =
        import ./settings/default.nix { inherit theme math lib color-lib; };
      extensions = with addons; [ sidebery ];
      userChrome = import ./userChrome-minimal.nix {
        inherit theme color-lib firefox-csshacks;
      };

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
