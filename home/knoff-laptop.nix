#NixOS, home-manager, system configuration, package installation, program enablement, system options.
{ inputs, outputs, lib, config, pkgs, ... }: {
  imports = [
    ./programs/editor/default.nix
    ./programs/terminal
    #./modules/sway
    ./modules/hyprland
    ./modules/eww

    ./programs/browser

    #./modules/firefox.nix


    ./programs/gaming/steam.nix
    ./enviroment.nix
    #./programs
    #./services
    #./desktop
    ./programs/virtualization/bottles.nix

    ./modules/thunderbird.nix
  ];
  disabledModules = ["programs/eww.nix"];
  programs.git = {
    enable = true;
    userName = "knoff";
    userEmail = "selby@niko.ink";
  };

  # firefox module
  #services.firefoxBrowser = {
  #  enable = true;
  #  profile = "knoff";
  #};

  #nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  programs.nix-index = {
    enable = true;
  };

  # TODO: move this to someplace more logical
  home.packages = with pkgs; [
    prismlauncher

    # move to desktop module?
    gnome.gnome-disk-utility

    wgnord

    # for xdg settings
    gimp
    mpv
  ];

  # XDG settings
  xdg.mimeApps = {
    enable = true;
    associations.added = {
      #"application/pdf" = [ "org.gnome.Evince.desktop" ];
      "video/mp4" = [ "mpv.desktop" ];
      # gimp:
      "image/bmp" = [ "org.gimp.GIMP.desktop" ];
      "image/gif" = [ "org.gimp.GIMP.desktop" ];
      "image/jpeg" = [ "org.gimp.GIMP.desktop" ];
      "image/png" = [ "org.gimp.GIMP.desktop" ];
      "image/svg+xml" = [ "org.gimp.GIMP.desktop" ];
      "image/tiff" = [ "org.gimp.GIMP.desktop" ];

    };
    defaultApplications = {
      #"application/pdf" = [ "org.gnome.Evince.desktop" ];
      "video/mp4" = [ "mpv.desktop" ];
      # gimp:
      "image/bmp" = [ "org.gimp.GIMP.desktop" ];
      "image/gif" = [ "org.gimp.GIMP.desktop" ];
      "image/jpeg" = [ "org.gimp.GIMP.desktop" ];
      "image/png" = [ "org.gimp.GIMP.desktop" ];
      "image/svg+xml" = [ "org.gimp.GIMP.desktop" ];
      "image/tiff" = [ "org.gimp.GIMP.desktop" ];
    };
  };

  services.emailManager = {
    enable = true;
    profile = "knoff";
  };

  programs.home-manager.enable = true;
  fonts.fontconfig.enable = true;

  nixpkgs = {
    overlays = builtins.attrValues outputs.overlays;
    #overlays = [
    # Add overlays your own flake exports (from overlays and pkgs dir):
    #outputs.overlays.additions
    #outputs.overlays.modifications
    #outputs.overlays.unstable-packages
    #];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (pkg: true);
    };

  };


  # ~ Battery
  # Battery status, and notifications
  services.batsignal.enable = true;


  home = {
    username = "knoff";
    homeDirectory = "/home/knoff";
  };

  # enable qt themes
  qt = {
    enable = true;
    platformTheme = "gtk3";
    style = {
      package = pkgs.adwaita-qt;
    };
  };

  # enable gtk themes
  gtk = {
    enable = true;
    theme = {
      name = "Orchis-Grey-Dark";
      package = pkgs.orchis-theme;
    };
    cursorTheme = {
      name = "Vanilla-DMZ";
      package = pkgs.vanilla-dmz;
    };
  };

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";

}

