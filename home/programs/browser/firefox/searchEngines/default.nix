{
  pkgs,
  lib,
}: {
  force = lib.mkOverride 1000 true;
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
  engines = {
    # -------------------- Nix Search --------------------
    "Nix Packages" = {
      urls = [
        {
          template = "https://search.nixos.org/packages";
          params = [
            {
              name = "type";
              value = "packages";
            }
            {
              name = "query";
              value = "{searchTerms}";
            }
            {
              name = "channel";
              value = "unstable";
            }
            {
              name = "size";
              value = "150";
            }
          ];
        }
      ];
      #icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/package.svg";
      definedAliases = ["!p"];
    };
    # -------------------- Nix Options --------------------
    "Nix Options" = {
      urls = [
        {
          template = "https://search.nixos.org/options";
          params = [
            {
              name = "type";
              value = "packages";
            }
            {
              name = "query";
              value = "{searchTerms}";
            }
            {
              name = "channel";
              value = "unstable";
            }
            {
              name = "size";
              value = "150";
            }
          ];
        }
      ];

      #icon =
      #  "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/cm_options.svg";
      definedAliases = ["!o"];
    };
    # -------------------- Nixos Wiki --------------------
    "NixOS Wiki" = {
      urls = [
        {
          template = "https://nixos.wiki/index.php";
          params = [
            {
              name = "search";
              value = "{searchTerms}";
            }
          ];
        }
      ];
      #iconUpdateURL = "https://nixos.wiki/favicon.png";
      #updateInterval = 24 * 60 * 60 * 1000; # every day
      #icon =
      #  "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
      definedAliases = ["!n"];
    };
    "Home-Manager" = {
      urls = [
        {
          template = "https://home-manager-options.extranix.com/?query={searchTerms}";
        }
      ];
      updateInterval = 24 * 60 * 60 * 1000; # every day
      #icon =
      #  "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/twitter-home.svg";
      definedAliases = ["!h"];
    };
    # -------------------- dev sites --------------------
    "StackOverflow" = {
      urls = [
        {
          template = "https://duckduckgo.com/";
          params = [
            {
              name = "q";
              value = "site%3Astackoverflow.com+{searchTerms}";
            }
          ];
        }
      ];
      # icon =
      #   "${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/stackoverflow.svg";
      definedAliases = ["!s"];
    };
    # -------------------- Github --------------------
    "Github" = {
      urls = [
        {
          template = "https://duckduckgo.com/";
          params = [
            {
              name = "q";
              value = "site%3Agithub.com+-issues+-topic+-releases+{searchTerms}";
            }
          ];
        }
      ];
      # icon =
      #   "${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/github.svg";
      definedAliases = ["!g"];
    };
    # -------------------- Nix Dots Searcher --------------------
    "NixDots" = {
      urls = [
        {
          template = "https://github.com/search?";
          params = [
            {
              name = "q";
              value = "lang%3ANix+{searchTerms}";
            }
            {
              name = "type";
              value = "code";
            }
          ];
        }
      ];
      # icon =
      #   "${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/github.svg";
      definedAliases = ["!nd"];
    };
    # -------------------- free information --------------------
    "fmhy" = {
      urls = [
        {
          template = "https://www.fmhy.tk/search";
          params = [
            {
              name = "q";
              value = "{searchTerms}";
            }
          ];
        }
      ];
      # icon = "${pkgs.circle-flags}/share/circle-flags-svg/other/pirate.svg";
      definedAliases = ["!f"];
    };
    # -------------------- Annas-Archive --------------------
    "Annas-Archive" = {
      urls = [
        {
          template = "https://annas-archive.org/search";
          params = [
            {
              name = "q";
              value = "{searchTerms}";
            }
          ];
        }
      ]; # https://annas-archive.org/favicon.ico
      #icon = "https://annas-archive.org/favicon.ico";
      updateInterval = 24 * 60 * 60 * 1000; # every day
      #icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/bookmark.svg";
      definedAliases = ["!a"];
    };
    # -------------------- Disable Defaults --------------------

    "bing".metaData.hidden = true;
    "google".metaData.hidden = true;
    "amazon.de".metaData.hidden = true;
    "wikipidia".metaData.hidden = true;
    "ddg".metaData.hidden = false;
  };
}
