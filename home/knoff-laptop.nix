#NixOS, home-manager, system configuration, package installation, program enablement, system options.
{
  outputs,
  inputs,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./programs/editor/default.nix
    ./programs/terminal # default
    ./programs/terminal/programs/pueue.nix
    ./programs/terminal/prompt.nix # starship
    #./modules/sway
    ./modules/hyprland
    #./modules/eww

    # Firefox
    ./programs/browser/firefox

    # music
    ./programs/media/audio/spotify.nix

    #./modules/firefox.nix

    ./programs/gaming/steam.nix
    ./programs/gaming/lutris.nix
    ./enviroment.nix
    #./programs
    #./services
    #./desktop
    ./programs/virtualization/bottles.nix

    ./modules/thunderbird.nix

    ./xdg-enviroment.nix
  ];

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

    (llm.withPlugins([pkgs.llm-cmd]))
    ttok

    evince

    obsidian

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
    ++ builtins.attrValues inputs.solara.overlays
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

  # enable qt themes
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
    #platformTheme.name = "gtk3";

    style = {
      name = "adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };

  # enable gtk themes
  gtk =
  let
    extra3-4Config = {
      gtk-application-prefer-dark-theme=1;
    };

  in
  {
    enable = true;
    theme = {
      name = "Fluent-Dark";
      package = pkgs.fluent-gtk-theme;
    };
    iconTheme = {
      name = "Fluent-Dark";
      package = pkgs.fluent-icon-theme;
    };
    cursorTheme = {
      name = "Vanilla-DMZ";
      package = pkgs.vanilla-dmz;
    };

    gtk3.extraConfig = extra3-4Config;
    gtk4.extraConfig = extra3-4Config;

  };

  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        #gtk-theme = "Adwaita-dark";
        #icon-theme = "Adwaita-dark";
        #cursor-theme = "Adwaita-dark";
      };
      "org/gnome/shell/extensions/user-theme" = {
        name = "Adwaita-dark";
      };
      "org/gnome/gedit/preferences/editor" = {
        scheme = "oblivion";
      };
      "org/gnome/Terminal/Legacy/Settings" = {
        theme-variant = "dark";
      };
    };
  };


  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
