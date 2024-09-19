#NixOS, home-manager, system configuration, package installation, program enablement, system options.
{
  outputs,
  self,
  pkgs,
  ...
}: {
  imports = [
    ./programs/editor/default.nix
    ./programs/terminal # default
    ./programs/terminal/programs/pueue.nix

    #./programs/terminal/prompt.nix # starship
    #./modules/sway
    ./modules/hyprland
    ./modules/ags
    #./modules/eww

    # Firefox
    ./programs/browser/firefox

    # music
    ./programs/media/audio/spotify.nix

    #./modules/firefox.nix

    #./programs/gaming/steam.nix
    ./programs/gaming/lutris.nix
    ./enviroment.nix
    #./programs
    #./services
    #./desktop
    ./programs/virtualization/bottles.nix

    ./modules/thunderbird.nix

    ./xdg-enviroment.nix
  ];

  services.playerctld.enable = true;

  wayland.windowManager.hyprlandCustom = {
    enable = true;
  };

  #disabledModules = ["programs/eww.nix"];
  programs.git = {
    enable = true;
    userName = "knoff";
    userEmail = "selby@niko.ink";

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
    (llm.withPlugins [self.packages.${pkgs.system}.llm-cmd])
    (self.packages.${pkgs.system}.ttok)

    skypeforlinux # -- skype phone
    audio-recorder

    evince

    obsidian # notes

    koodo-reader # books

    prismlauncher

    kdePackages.breeze-icons
    kdePackages.grantleetheme
    libsForQt5.grantleetheme
    wgnord

    telegram-desktop

    prusa-slicer
  ];

  services.emailManager = {
    enable = true;
    profile = "knoff";
  };

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
  services.batsignal.enable = true;

  home = {
    username = "knoff";
    homeDirectory = "/home/knoff";
  };


  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
