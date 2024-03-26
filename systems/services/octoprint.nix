{pkgs, ...}:
{
  services.octoprint = {
    enable = true;
    openFirewall = true;
    plugins = plugins: with plugins; [
      themeify stlviewer
    ];

    user = "octoprint";

  };


  # octoprint user groups. needs video
  users.users.octoprint = {
    extraGroups = [ "video" ];
  };
}

