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
            # Essential
            ublock-origin
            bitwarden
            #onepassword-password-manager
            sidebery
            tridactyl
            # Privacy
            smart-referer
            cookie-autodelete
            user-agent-string-switcher

            firefox-color
          ];
          settings."FirefoxColor@mozilla.com".settings = {
            firstRunDone = true;
            theme = {
              title = "ASFASF";
              images.additional_backgrounds = ["./bg-000.svg"];
              colors = {
                toolbar = "#${theme.dark.base00}";
                toolbar_text = "#${theme.dark.base05}";
                frame = "#${theme.dark.base01}";
                tab_background_text = "#${theme.dark.base05}";
                toolbar_field = "#${theme.dark.base02}";
                toolbar_field_text = "#${theme.dark.base05}";
                tab_line = "#${theme.dark.base0D}";
                popup = "#${theme.dark.base00}";
                popup_text = "#${theme.dark.base05}";
                button_background_active = "#${theme.dark.base04}";
                frame_inactive = "#${theme.dark.base00}";
                icons_attention = "#${theme.dark.base0D}";
                icons = "#${theme.dark.base05}";
                ntp_background = "#${theme.dark.base00}";
                ntp_text = "#${theme.dark.base05}";
                popup_border = "#${theme.dark.base0D}";
                popup_highlight_text = "#${theme.dark.base05}";
                popup_highlight = "#${theme.dark.base04}";
                sidebar_border = "#${theme.dark.base0D}";
                sidebar_highlight_text = "#${theme.dark.base05}";
                sidebar_highlight = "#${theme.dark.base0D}";
                sidebar_text = "#${theme.dark.base05}";
                sidebar = "#${theme.dark.base00}";
                tab_background_separator = "#${theme.dark.base0D}";
                tab_loading = "#${theme.dark.base05}";
                tab_selected = "#${theme.dark.base00}";
                tab_text = "#${theme.dark.base05}";
                toolbar_bottom_separator = "#${theme.dark.base00}";
                toolbar_field_border_focus = "#${theme.dark.base0D}";
                toolbar_field_border = "#${theme.dark.base00}";
                toolbar_field_focus = "#${theme.dark.base00}";
                toolbar_field_highlight_text = "#${theme.dark.base00}";
                toolbar_field_highlight = "#${theme.dark.base0D}";
                toolbar_field_separator = "#${theme.dark.base0D}";
                toolbar_vertical_separator = "#${theme.dark.base0D}";
              };
            };
          };
        };

        # userContent = ''
        #   /* Firefox profile directory/chrome/userContent.css */
        #   /* Apply to all about: pages, including about:home and about:newtab */
        #   @-moz-document url-prefix("about:") {
        #     #root,
        #     .newtab-main,
        #     .outer-wrapper {
        #       background-color: #${theme.dark.base00} !important;  /* Dark background color */
        #       color: #${theme.dark.base07} !important;             /* Text color */
        #     }

        #     /* Optional: Remove background images from new tab page */
        #     .wallpaper-input[style*="background-image"] {
        #       background-image: none !important;
        #     }
        #   }
        # '';

        userChrome =
          import ./userChrome.nix {inherit theme color-lib firefox-csshacks;};
        search = import ./searchEngines {inherit pkgs lib;};
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
        search = import ./searchEngines {inherit pkgs lib;};
      };

      "testing2" = {
        isDefault = false;
        id = 2;
        name = "testing2";

        settings =
          import ./settings/default.nix {inherit theme lib color-lib;};
        extensions.packages = with addons; [sidebery];
        userChrome = import ./userChrome.nix {
          inherit theme color-lib firefox-csshacks;
        };
      };

      "projection" = {
        isDefault = false;
        id = 3;
        name = "projection";

        settings =
          import ./settings/default.nix {inherit theme lib color-lib;};
        extensions.packages = with addons; [sidebery];
        userChrome = import ./userChrome-minimal.nix {
          inherit theme color-lib firefox-csshacks;
        };
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
