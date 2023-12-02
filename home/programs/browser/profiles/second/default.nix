{ pkgs, config, inputs, lib, ... }:
let
  # unsigned int
  id = 1;

  # computers name
  profileName = "${config.home.username}-${toString id}";

  # Your firefox install path
  firefoxPath = ".mozilla/firefox";

  # The location of your firefox config
  profilePath = "${firefoxPath}/${profileName}";

  # Firefox Addons, may want to change this at some point
  addons = inputs.firefox-addons.packages.${pkgs.system};




  Vertical-Tabs = pkgs.fetchFromGitHub {
    owner = "ranmaru22";
    repo = "firefox-vertical-tabs";
    rev = "d1405cfb51e21dd7bfb8b7c5fcb3925faab2fe99";
    sha256 = "sha256-ua4r3dzSj+atPpR2qlm0CtyfMVUOaw3wUf6m5wluqd4=";
  };

  # linux side-bar mods?
  VerticalFox = pkgs.fetchFromGitHub {
    owner = "christorange";
    repo = "VerticalFox";
    rev = "9f993ae6a75f5efd56f927d82c66393f1817a9b1";
    sha256 = "sha256-1urPrffIw6YFINpCaGxMo7+7lBAnGKGjc3BBS9I0UzQ=";
  };


  # Side-Berry User-style
  sideberryRepo = pkgs.fetchFromGitHub {
    owner = "drannex42";
    repo = "FirefoxSidebar";
    rev = "d99c43774b56226834c273c131563dfa9625f58d";
    sha256 = "sha256-LMqmawJbPc8trFYhxRHG1i24R62CZa5wj9+J6yejhCY=";
  };





in
{


  home.file = {
    "sideberry" = {
      source = "${sideberryRepo}";
      target = "${profilePath}/chrome/sideberry";
    };
    "VerticalFox" =
      {
        source = "${VerticalFox}";
        target = "${profilePath}/chrome/VerticalFox";
      };
    "Vertical-Tabs" =
      {
        source = "${Vertical-Tabs}";
        target = "${profilePath}/chrome/Vertical-Tabs";
      };
  };

  #home.file."${profilePath}/chrome/sidebar-mods.css".text = builtins.readFile

  #home.file."${profilePath}/chrome/treestyletab-edge-mimicry.css".text =

  programs.firefox = {
    profiles.${profileName} = {
      inherit id;
      name = "${profileName}";

      extensions = with addons; [
        # Privacy and Security
        #        ublock-origin
        #        anonaddy
        #        clearurls
        #        privacy-possum
        #        decentraleyes
        #        darkreader
        #        sponsorblock
        #        i-dont-care-about-cookies
        #        consent-o-matic
        # bitwarden
        # canvasblocker
        # cookie-autodelete

        # Productivity
        #        violentmonkey
        # tree-style-tab
        # sidebery
        #        smart-referer
        #        user-agent-string-switcher
        #        single-file
        #        nighttab
        #        rust-search-extension
        #        translate-web-pages

        # Steam-related packages
        #        augmented-steam
        #        protondb-for-steam
        #        steam-database

        # Github-related packages
        #        enhanced-github
        #        lovely-forks

        # Youtube-related packages
        #        youtube-shorts-block

      ];

      # @import "./sideberry/userChrome.css";
      userChrome = ''
      '';
      userContent = ''
      '';

      #      settings = import ./settings.nix;
    };
  };
}
