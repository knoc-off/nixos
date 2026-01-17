{
  inputs,
  pkgs,
  theme,
  lib,
  color-lib,
  config,
  ...
}: let
  addons = inputs.firefox-addons.packages.${pkgs.system};

  firefox-csshacks = pkgs.stdenv.mkDerivation {
    name = "patched-firefox-csshacks";
    src = inputs.firefox-csshacks;
    installPhase = ''
      cp -r . $out
    '';
  };

  userChrome = let
    chrome = import ./chrome.nix {inherit pkgs lib;} {inherit firefox-csshacks;};
  in
    chrome.mkUserChrome [
      (chrome.autohide_sidebar.overrideAttrs (old: {
        postPatch = ''
          substituteInPlace source.css \
            --replace-fail "--uc-sidebar-hover-width: 210px" "--uc-sidebar-hover-width: 25vw" \
            --replace-fail "--uc-autohide-sidebar-delay: 600ms" "--uc-autohide-sidebar-delay: 100ms" \
            --replace-fail "--uc-autohide-transition-duration: 115ms" "--uc-autohide-transition-duration: 200ms" \
            --replace-fail "--uc-autohide-transition-type: linear" "--uc-autohide-transition-type: ease-in-out"
            # --replace-fail "--uc-sidebar-width: 40px" "--uc-sidebar-width: 38px" \
        '';
        postInstall = ''
          cat >> $out << 'EOF'
          #sidebar-box { z-index: 3 !important; }
          #sidebar-header { display: none; }
          EOF
        '';
      }))

      chrome.autohide_bookmarks_toolbar
      chrome.auto_devtools_theme_for_rdm
      chrome.hide_tabs_toolbar_v2

      (chrome.mkCustom ''
        :root {
          --panel-width: 100vw;
          --panel-hide-offset: -30px;
          --opacity-when-hidden: 0.0;
        }

        #TabsToolbar { visibility: collapse; }
        .titlebar-buttonbox-container,
        .titlebar-spacer[type="post-tabs"] { display: none; }

        #sidebar-header {
          display: none !important;
        }
      '')
    ];
in rec {
  home.sessionVariables = {BROWSER = "firefox";};

  programs.firefox = {
    enable = true;
    profiles = {
      "main" = {
        isDefault = true;
        id = 0;
        name = "main";

        # Extensions for the main profile
        extensions = {
          force = true;
          packages = with addons; [
            sidebery

            ublock-origin
            bitwarden
            # onepassword-password-manager
            # tridactyl
            # Privacy
            smart-referer
            # cookie-autodelete
            # user-agent-string-switcher

            dearrow
            # fake-filler
            imagus-mod
            sponsorblock
            violentmonkey

            firefox-color
          ];
          settings = import ./settings/extensionSettings.nix {inherit color-lib theme;};
        };

        inherit userChrome;

        settings = import ./settings/default.nix {inherit theme lib color-lib;};
        search = import ./searchEngines {inherit pkgs lib;};
      };

      "minimal" = {
        isDefault = false;
        id = 1;
        name = "minimal";

        # Extensions for the minimal profile
        extensions = {
          force = true;
          packages = with addons; [
            # Essential
            ublock-origin
            bitwarden
            sidebery
            tridactyl

            firefox-color
          ];
          settings = import ./settings/extensionSettings.nix {inherit color-lib theme;};
        };

        inherit userChrome;

        settings = import ./settings/default.nix {inherit theme lib color-lib;};
        search = import ./searchEngines {inherit pkgs lib;};
      };
    };
  };

  # auto generate the desktop entries for each profile (Linux only)
  xdg.desktopEntries = lib.mkIf pkgs.stdenv.isLinux (let
    mkFirefoxDesktopEntry = profile: {
      name = "Firefox (${profile.name})";
      genericName = "Web Browser";
      exec = "${pkgs.firefox}/bin/firefox -P ${profile.name}";
      icon = "${pkgs.firefox}/lib/firefox/browser/chrome/icons/default/default128.png";
      type = "Application";
      categories = ["Network" "WebBrowser"];
      mimeType = ["text/html" "text/xml"];
    };
  in
    lib.mapAttrs (name: profile: mkFirefoxDesktopEntry profile)
    programs.firefox.profiles
    // {
      firefox-private = {
        name = "Firefox Private";
        genericName = "Web Browser";
        exec = "${pkgs.firefox}/bin/firefox --private-window";
        icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
        type = "Application";
        categories = ["Network" "WebBrowser"];
        mimeType = ["text/html" "text/xml"];
      };
    });
}
