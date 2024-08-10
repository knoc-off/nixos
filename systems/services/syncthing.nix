{ config, pkgs, ... }:

{
  services.syncthing = {
    enable = true;

    settings = {
      devices = {
        "phone" = {
          id = "NWTJXBI-ID2JZB3-P5CBD4N-5KGCGHD-QO5D6S5-WZ5YCZ3-64J45SV-W4ZVJAN";  # Replace with your phone's device ID
          addresses = ["dynamic"];
          introducer = true;
          autoAcceptFolders = true;
        };
      };

      folders = {
        # You can add specific folders here if needed
        # By default, Syncthing will create a "Default Folder" in its data directory
      };

      options = {
        globalAnnounceEnabled = false;  # Disable global discovery for added security
        localAnnounceEnabled = true;
        urAccepted = -1;  # Disable usage reporting
        relaysEnabled = true;
        autoAcceptFolders = true;
      };
      openDefaultPorts = true;
      gui = {
        address = "127.0.0.1:8384";
        tls = false;
      };
    };
  };

}
