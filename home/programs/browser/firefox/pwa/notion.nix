{ pkgs, ... }:

{
  programs.firefoxpwa = {
    enable = true;

    profiles."01KK133W749B17DS3ZKF6Z5KK3" = {
      name = "notion";

      sites."01KK133W74D3B043PK487V75CK" = {
        name = "Notion";
        url = "https://www.notion.so";
        manifestUrl = "https://www.notion.so/manifest.json";

        desktopEntry = {
          icon = pkgs.fetchurl {
            url = "https://upload.wikimedia.org/wikipedia/commons/4/45/Notion_app_logo.png";
            sha256 = "1gnm4ib1i30winhz4qhpyx21syp9ahhwdj3n1l7345l9kmjiv06s";
          };
          categories = [ "Office" "ProjectManagement" ];
        };
      };
    };
  };
}
