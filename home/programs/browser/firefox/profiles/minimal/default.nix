{ theme
, pkgs
, inputs
, ...
}:
let
  # unsigned int
  id = 1;

  # computers name
  profileName = "minimal";

  # Firefox Addons, may want to change this at some point
  addons = inputs.firefox-addons.packages.${pkgs.system};
in
{
  programs.firefox = {
    profiles.${profileName} = {
      isDefault = false;
      inherit id;
      name = "${profileName}";

      extensions = with addons; [
        # Privacy and Security
        ublock-origin
        bitwarden

        # Appearance / functionality
        darkreader
        nighttab

        # Privacy / Security
        smart-referer
        #history-cleaner # deletes history older than <time>
        #user-agent-string-switcher

        # Quality of life
        translate-web-pages
        #export-cookies-txt # exports cookies to a txt file, used for curl, etc.

        #istilldontcareaboutcookies # deletes popups, not super needed with ublock.
        #cookie-autodelete # deletes cookies when tab is closed

        # remove tabs completely
        adsum-notabs

        #tridactyl # best vim plugin

        kagi-search
        violentmonkey
      ];

      search = {
        force = true;
        default = "Kagi";
      };

      search.engines = import ./searchEngines.nix { inherit pkgs; };
      userChrome = import ./userChrome.nix { inherit theme pkgs; };
      userContent = import ./userContent.nix { inherit theme; };
      settings = import ./settings.nix { inherit theme; };

    };
  };
}
