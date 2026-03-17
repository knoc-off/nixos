{pkgs, lib, ...}: let
  siteId = "01KKXEEWVREDYJ3X338T18WHA1";
  profileId = "01KKXEEWVRNGQZ59XWMP4TM65T";
in {
  programs.firefoxpwa = {
    enable = true;

    profiles.${profileId} = {
      name = "linear";

      sites.${siteId} = {
        name = "Linear";
        url = "https://linear.app";
        manifestUrl = "https://linear.app/static/pwa.webmanifest?v=4";

        desktopEntry = {
          icon = pkgs.fetchurl {
            url = "https://linear.app/icons/icon-192x192.png";
            sha256 = "0a95w16c43swynall1zkj2fn2vzcj5djnw3dyz487k8nw78afssw";
          };
          categories = ["Office" "ProjectManagement"];
        };
      };
    };
  };

  # Inject Firefox prefs into the PWA profile for dark theme support and panel fixes
  xdg.dataFile."firefoxpwa/profiles/${profileId}/user.js".text = ''
    user_pref("ui.systemUsesDarkTheme", 1);
    user_pref("devtools.theme", "dark");
    user_pref("browser.theme.content-theme", 0);
    user_pref("layout.css.prefers-color-scheme.content-override", 0);
    user_pref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");
    user_pref("widget.gtk.ignore-bogus-leave-notify", 1);
    user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);
  '';
}
