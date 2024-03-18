{ pkgs }:
{
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
    icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/package.svg";
    definedAliases = [ "!p" ];
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

    icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/cm_options.svg";
    definedAliases = [ "!o" ];
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
    icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
    definedAliases = [ "!n" ];
  };
  "Home-Manager" = {
    urls = [{ template = "https://home-manager-options.extranix.com/?query={searchTerms}"; }];
    updateInterval = 24 * 60 * 60 * 1000; # every day
    icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/twitter-home.svg";
    definedAliases = [ "!h" ];
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
    icon = "${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/stackoverflow.svg";
    definedAliases = [ "!s" ];
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
    icon = "${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/github.svg";
    definedAliases = [ "!g" ];
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
    icon = "${pkgs.circle-flags}/share/circle-flags-svg/other/pirate.svg";
    definedAliases = [ "!f" ];
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
    iconUpdateURL = "https://annas-archive.org/favicon.ico";
    updateInterval = 24 * 60 * 60 * 1000; # every day
    #icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/bookmark.svg";
    definedAliases = [ "!a" ];
  };
  # -------------------- alternate search engines --------------------
  "Kagi-discuss" = {
    urls = [
      {
        template = "https://kagi.com/discussdoc";
        params = [
          {
            name = "target_language";
            value = "english";
          }
          {
            name = "summary";
            value = "takeaway";
          }
          {
            name = "url";
            value = "{searchTerms}";
          }
        ];
      }
    ];
    iconUpdateURL = "https://kagi.com/favicon.ico";
    updateInterval = 24 * 60 * 60 * 1000; # every day
    #icon = "${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/kaggle.svg";
    definedAliases = [ "!k" ];
  };
  # -------------------- Kagi Search --------------------
  "Kagi" = {
    urls = [
      {
        template = "https://kagi.com/search";
        params = [
          {
            name = "q";
            value = "{searchTerms}";
          }
          #{ name = "r"; value = "no_region"; }
        ];
      }
    ];
    iconUpdateURL = "https://kagi.com/favicon.ico";
    updateInterval = 24 * 60 * 60 * 1000; # every day
    #icon = "${pkgs.super-tiny-icons}/share/icons/SuperTinyIcons/svg/kaggle.svg";
    definedAliases = [ ];
  };

  # -------------------- Disable Defaults --------------------

  "Bing".metaData.hidden = true;
  "Google".metaData.hidden = true;
  "Amazon.de".metaData.hidden = true;
  "Wikipidia (en)".metaData.hidden = true;
  "DuckDuckGo".metaData.hidden = false;
}
