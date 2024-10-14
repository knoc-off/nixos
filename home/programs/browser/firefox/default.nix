{ inputs, pkgs, theme, lib, colorLib, ... }:
let

  addons = inputs.firefox-addons.packages.${pkgs.system};

  firefox-csshacks = pkgs.stdenv.mkDerivation {
    name = "patched-firefox-csshacks";
    src = inputs.firefox-csshacks;
    installPhase = ''
      cp -r . $out
    '';
  };
in {
  programs.firefox = {
    enable = true;
    profiles."main" = {
      isDefault = true;
      id = 0;
      name = "main";

      # addons
      extensions = import ./addons { inherit addons; };

      userChrome = import ./userChrome.nix { inherit theme colorLib firefox-csshacks;  };

      # custom search engines, default, etc.
      search.engines = import ./searchEngines { inherit pkgs; };
      search = {
        force = true;
        default = "duckduckgo";
        order = [
          "Annas-Archive"
          "NixOS Wiki"
          "Nix Packages"
          "Nix Options"
          "Home-Manager"
          "StackOverflow"
          "Github"
          "fmhy"
        ];
      };

    };
    profiles."minimal" = {
      isDefault = false;
      id = 1;
      name = "minimal";

      # addons
      extensions = import ./addons/minimal.nix { inherit addons; };

      # custom search engines, default, etc.
      search.engines = import ./searchEngines { inherit pkgs; };
      search = {
        force = true;
        default = "duckduckgo";
        order = [
          "Annas-Archive"
          "NixOS Wiki"
          "Nix Packages"
          "Nix Options"
          "Home-Manager"
          "StackOverflow"
          "Github"
          "fmhy"
        ];
      };
    };
    profiles."testing" = {
      isDefault = false;
      id = 2;
      name = "testing";

      extensions = import ./addons { inherit addons; };
      userChrome = import ./userChrome.nix { inherit theme colorLib firefox-csshacks;  };
    };
  };

  xdg.desktopEntries = {
    firefox-testing = {
      name = "Firefox-testing";
      genericName = "Web Browser";
      exec = "firefox -p testing %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = [ "Application" "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
    firefox-minimal = {
      name = "Firefox-minimal";
      genericName = "Web Browser";
      exec = "firefox -p minimal %U";
      icon = "${pkgs.firefox}/share/icons/hicolor/128x128/apps/firefox.png";
      terminal = false;
      categories = [ "Application" "Network" "WebBrowser" ];
      mimeType = [ "text/html" "text/xml" ];
    };
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
