{
  inputs,
  pkgs,
  libs,
  config,
  ...
}: {
  # should move all of the following to their own files.
  home.packages = with pkgs; [
    # Miscellaneous
    fuzzel

    # File-Managers
    #xfce.thunar
    #pcmanfm
  ];

  programs.nix-index.enable = true;

  services.easyeffects = {
    enable = true;
  };

  programs = {
    direnv = {
      enable = true;
      nix-direnv = {
        enable = true;
      };
    };
  };

  programs.git = {
    enable = true;
    userEmail = "nixos-git@knoc.one";
    userName = "knoff";

    extraConfig = {
      push = {
        autoSetupRemote = "true";
      };
    };
  };

  programs.home-manager.enable = true;
}
