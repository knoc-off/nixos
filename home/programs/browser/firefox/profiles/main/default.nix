{ theme
, pkgs
, inputs
, ...
}:
let
  # unsigned int
  id = 0;

  # computers name
  profileName = "main";

  # Firefox Addons, may want to change this at some point
  addons = inputs.firefox-addons.packages.${pkgs.system};
in
{

  home.packages = with pkgs; [
    pkgs.tridactyl-native
  ];

  programs.firefox = {
    package = pkgs.firefox.override {
      # See nixpkgs' firefox/wrapper.nix to check which options you can use
      nativeMessagingHosts = [
        # Gnome shell native connector
        #pkgs.gnome-browser-connector
        # Tridactyl native connector
        pkgs.tridactyl-native
      ];
    };

    profiles.${profileName} = {
      isDefault = true;
      inherit id;
      name = "${profileName}";

      extensions = with addons; [
        # Privacy and Security
        ublock-origin
        bitwarden

        # Appearance / functionality
        sidebery
        darkreader
        nighttab

        # Privacy / Security
        smart-referer
        history-cleaner # deletes history older than <time>
        user-agent-string-switcher

        # Quality of life
        translate-web-pages
        export-cookies-txt # exports cookies to a txt file, used for curl, etc.

        istilldontcareaboutcookies # deletes popups, not super needed with ublock.
        cookie-autodelete # deletes cookies when tab is closed

        tridactyl # best vim plugin
        #forget_me_not # deletes all website data

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
