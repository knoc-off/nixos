{ lib, inputs, config, pkgs, outputs, ... }:

{
  imports = [
    # Hardware configs
    ./hardware/hardware-configuration.nix
    ./hardware/bluetooth.nix
    ./hardware/fingerprint

    # Lanzaboot
    inputs.lanzaboote.nixosModules.lanzaboote

    # Sops
    inputs.sops-nix.nixosModules.sops
    {
      sops.defaultSopsFile = ./secrets/framework13/default.yaml;
      # This will automatically import SSH keys as age keys
      sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    }

    # Pipewire / Audio
    ./modules/audio

    # Nix package settings
    ./modules/nix.nix

    # Window manager
    ./modules/hyprland

    # This is an 'auto generated' file that should add a message to the build versions in the boot menu
    ./commit-messages/framework13-commit-message.nix

    # Android emulation
    #./modules/virtualisation/waydroid.nix
    ./modules/gtk
  ];

  programs = {
    steam = {
      enable = true;
      package = pkgs.steam-scaling;
    };
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };
    nix-ld = {
      enable = true;
      libraries = with pkgs; [ stdenv.cc.cc SDL2 SDL2_image libz ];
    };
    dconf.enable = true;
  };

  services = {
    # Yubikey
    yubikey-agent.enable = true;
    pcscd.enable = true;
    udev.packages = [ pkgs.yubikey-personalization ];

    # Pretty much just needed this for Steam
    flatpak.enable = true;

    # Fix wg-quick?
    resolved.enable = true;

    gtkThemeSymlinks = {
      enable = true;
      gtk2 = {
        themeName = "Fluent-Dark";
        themePackage = pkgs.fluent-gtk-theme;
      };
      gtk3 = {
        themeName = "Fluent-Dark";
        themePackage = pkgs.fluent-gtk-theme;
      };
      gtk4 = {
        themeName = "Fluent-Dark";
        themePackage = pkgs.fluent-gtk-theme;
      };
      symlinks = {
        "gtk-2.0/gtkrc" = pkgs.writeText "gtkrc" "gtk-application-prefer-dark-theme=1";
        "gtk-3.0/settings.ini" = pkgs.writeText "gtk3-settings.ini" ''
          [Settings]
          gtk-application-prefer-dark-theme=1
          gtk-error-bell=false
        '';
        "gtk-4.0/settings.ini" = pkgs.writeText "gtk4-settings.ini" ''
          [Settings]
          gtk-application-prefer-dark-theme=1
          gtk-error-bell=false
        '';
      };
    };

    fwupd.enable = true;

    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };

    xserver.xkb.layout = "us";

    printing = {
      enable = true;
      drivers = with pkgs; [
        hplip
        gutenprint
        foo2zjs
      ];
    };

    avahi = {
      enable = true;
      nssmdns4 = true;
    };

    libinput.enable = true;

    logind.extraConfig = ''
      HandlePowerKey=lock
    '';
  };

  environment = {
    systemPackages = with pkgs; [
      gnome.adwaita-icon-theme
      yubioath-flutter
      git
      wget
      home-manager
      libinput
    ];
    etc."current-system-packages".text = let
      packages = builtins.map (p: "${p.name}") config.environment.systemPackages;
      sortedUnique = builtins.sort builtins.lessThan (lib.unique packages);
      formatted = builtins.concatStringsSep "\n" sortedUnique;
    in formatted;
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    initrd.systemd.dbus.enable = true;
    loader = {
      systemd-boot.enable = if config.boot.lanzaboote.enable then lib.mkForce false else true;
      efi.canTouchEfiVariables = true;
    };
  };

  networking = {
    hostName = "framework";
    networkmanager.enable = true;
  };

  nixpkgs = {
    config.allowUnfree = true;
    overlays = builtins.attrValues outputs.overlays;
  };

  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    packages = with pkgs; [ terminus_font ];
    font = "${pkgs.terminus_font}/share/consolefonts/ter-i22b.psf.gz";
    keyMap = lib.mkDefault "us";
    useXkbConfig = true;
  };

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk
      noto-fonts-emoji
      liberation_ttf
      fira-code
      fira-code-symbols
      mplus-outline-fonts.githubRelease
      dina-font
      proggyfonts
      (nerdfonts.override { fonts = [ "FiraCode" ]; })
    ];
    fontconfig.defaultFonts = {
      monospace = [ "FiraCode Nerd Font Mono" ];
    };
  };

  users.users.knoff = {
    isNormalUser = true;
    shell = if config.programs.zsh.enable then pkgs.zsh
            else if config.programs.fish.enable then pkgs.fish
            else pkgs.bash;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    hashedPassword = "$y$j9T$jtFWvdQ6ghoncJ8srfdQn0$JN8OSftIfzHQmSpIZqeQyeK/Nrb8OQCbET5x2n82Yr9";
    openssh.authorizedKeys.keys = [ ];
  };

  users.users.root.openssh.authorizedKeys.keys = [ ];

  system.stateVersion = "23.11";
}
