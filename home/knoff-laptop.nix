#NixOS, home-manager, system configuration, package installation, program enablement, system options.
{ inputs, outputs, lib, config, pkgs, ... }: {
  imports = [
    ./programs/editor/default.nix
    ./programs/terminal/shell
    ./modules/sway
    #./programs
    #./services
    #./desktop
    #./desktop/hyprland
    #./enviroment.nix
  ];

  programs.home-manager.enable = true;

  nixpkgs = {
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      #outputs.overlays.additions
      #outputs.overlays.modifications
      #outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (pkg: true);
    };

  };


  home = {
    username = "knoff";
    homeDirectory = "/home/knoff";
  };

  # enable qt themes
#  qt = {
#    enable = true;
#    platformTheme = "gtk";
#    style = {
#      package = pkgs.adwaita-qt;
#    };
#  };
#
#  # enable gtk themes
#  gtk = {
#    enable = true;
#    theme = {
#      name = "Materia-dark";
#      package = pkgs.materia-theme;
#    };
#  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";

}
