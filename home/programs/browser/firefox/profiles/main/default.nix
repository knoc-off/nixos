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
      nativeMessagingHosts = [
        # Tridactyl native client
        pkgs.tridactyl-native
      ];
    };

    profiles.${profileName} = {
      isDefault = true;
      inherit id;
      name = "${profileName}";

      extensions = with addons; [
        # Privacy and Security
        ublock-origin # best ad blocker
        bitwarden     # need this.

        # Appearance / functionality
        sidebery    # 10/10 need this
        darkreader  # darkmode everywhere
        nighttab    # can remove.

        # Privacy / Security
        smart-referer   # give out less data
        history-cleaner # deletes history older than <time>
        user-agent-string-switcher # disguise yourself

        # Quality of life
        translate-web-pages # good translater. might swap to firefox inbuilt
        export-cookies-txt  # exports cookies to a txt file, used for curl, etc.

        istilldontcareaboutcookies # deletes popups, not super needed with ublock.
        cookie-autodelete # deletes cookies when tab is closed

        tridactyl # best vim plugin

        # Kagi addon - Addon hardly works. :(
        kagi-search

        # user script manager.
        violentmonkey
      ];

      # custom search engines, default, etc.
      search = import ./searchEngines.nix { inherit pkgs; };
      # theme for the firefox ui
      userChrome = import ./userChrome.nix { inherit theme pkgs; };
      # theme for the content firefox presents.
      userContent = import ./userContent.nix { inherit theme; };
      # settings for firefox. telemetry, scrolling, etc.
      settings = import ./settings.nix { inherit theme; };

    };
  };
}
