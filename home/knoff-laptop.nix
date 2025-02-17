#NixOS, home-manager, system configuration, package installation, program enablement, system options.
{
  outputs,
  self,
  pkgs,
  user,
  ...
}: {
  imports = [
    ./programs/terminal # default
    ./programs/terminal/programs/pueue.nix

    ./programs/terminal/shell

    ./programs/media/video/mpv.nix

    ./programs/filemanager/yazi.nix

    ./programs/editor/default.nix

    # Desktop and widgets
    ./modules/hyprland
    ./modules/ags

    # Firefox
    ./programs/browser/firefox

    # music
    ./programs/media/audio/spotify.nix

    #./modules/firefox.nix

    ./programs/gaming/lutris.nix
    ./enviroment.nix

    self.homeModules.gtk

    #./programs
    #./desktop
    #./programs/virtualization/bottles.nix

    ./modules/thunderbird.nix

    ./xdg-enviroment.nix
  ];


  services = {
    syncthing.enable = true;
    playerctld.enable = true;
    emailManager = {
      enable = true;
      profile = "${user}";
    };
    batsignal.enable = true;

  };



  wayland.windowManager.hyprlandCustom = {
    enable = true;
  };

  #disabledModules = ["programs/eww.nix"];
  programs.git = {
    enable = true;
    userName = "${user}";
    userEmail = "selby@niko.ink";
    lfs.enable = true;

    extraConfig = {
      push = {
        autoSetupRemote = "true";
      };
    };
  };

  programs.nix-index = {
    enable = true;
  };

  # TODO: move this to someplace more logical
  home.packages = with pkgs; [
    (pkgs.python3.withPackages (ps: [ ps.llm self.packages.${pkgs.system}.llm-cmd ]))

    (self.packages.${pkgs.system}.ttok)

    skypeforlinux # skype phone
    audio-recorder

    evince

    obsidian # notes

    koodo-reader # books

    prismlauncher

    kdePackages.breeze-icons
    kdePackages.grantleetheme
    libsForQt5.grantleetheme

    gnome-calculator

    telegram-desktop

    prusa-slicer
  ];


  programs.home-manager.enable = true;
  fonts.fontconfig.enable = true;

  nixpkgs = {
    overlays =
      [
      ]
      ++ builtins.attrValues outputs.overlays;

    config = {
      allowUnfree = true;
      allowUnfreePredicate = _pkg: true;
    };
  };

  # ~ Battery
  # Battery status, and notifications
  home = {
    username = "${user}";
    homeDirectory = "/home/${user}";
  };


  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
