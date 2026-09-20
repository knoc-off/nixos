# Search engine config for firefox-neo. Deliberately not shared with
# modules/firefox/searchEngines -- that one is used by niko/thinkpad-work too
# and carries a longer engine list; this one is trimmed to what's actually
# used day to day.
#
# The Kagi entry has no session token wired up here -- it's logged into
# imperatively (just sign in through the browser) rather than provisioned via
# a Nix secret.
{ pkgs, lib }:
{
  force = lib.mkOverride 1000 true;
  default = "Kagi";
  order = [
    "Kagi"
    "ddg"
    "Nix Packages"
    "Nix Options"
    "Home-Manager"
  ];
  engines = {
    "Kagi" = {
      urls = [
        {
          template = "https://kagi.com/search";
          params = [
            {
              name = "q";
              value = "{searchTerms}";
            }
          ];
        }
      ];
      icon = pkgs.fetchurl {
        url = "https://kagi.com/apple-touch-icon.png";
        hash = "sha256-1XQib7Lok2vCZpm7jr0Tqzy7ZcLZ5epLGFTjf7y8gps=";
      };
    };

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

    "Home-Manager" = {
      urls = [
        {
          template = "https://home-manager-options.extranix.com/?query={searchTerms}";
        }
      ];
      updateInterval = 24 * 60 * 60 * 1000; # every day
      icon = "${pkgs.kora-icon-theme}/share/icons/kora/actions/16/twitter-home.svg";
      definedAliases = [ "!h" ];
    };

    "bing".metaData.hidden = true;
    "google".metaData.hidden = true;
    "amazon.de".metaData.hidden = true;
    "wikipidia".metaData.hidden = true;

    "ddg" = {
      metaData.hidden = false;
      icon = pkgs.fetchurl {
        url = "https://duckduckgo.com/favicon.ico";
        hash = "sha256-2ZT4BrHkIltQvlq2gbLOz4RcwhahmkMth4zqPLgVuv0=";
      };
    };
  };
}
