{ lib, inputs, outputs, colorLib, theme, config, pkgs, self, hostName, system, ... }: {
  imports = [

    { # Home-Manager
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = false;
        useUserPackages = true;
        users.knoff = import ../home/knoff-laptop.nix;
        extraSpecialArgs = {
          inherit inputs outputs self theme colorLib hostName system;
        };
      };
    }

    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-gpu-amd
    inputs.hardware.nixosModules.common-pc-ssd

    { boot.binfmt.emulatedSystems = [ "aarch64-linux" ]; }

    inputs.disko.nixosModules.disko
    { disko.devices.disk.main.device = "/dev/nvme0n1"; }
    ./hardware/disks/bcachefs.nix

    # Hardware configs
    ./hardware/hardware-configuration.nix

    ./hardware/boot.nix

    ./modules/misc.nix

    # Pipewire / Audio
    ./modules/audio

    # Nix package settings
    ./modules/nix.nix

    # Window manager
    self.nixosModules.windowManager.hyprland # maybe remove

    ./modules/gtk

    # enable bash shell customizations
    ./modules/shell/bash.nix
  ];


  programs = {
    # allows running of arbitrary programs.
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
    #flatpak.enable = true;

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
        "gtk-2.0/gtkrc" =
          pkgs.writeText "gtkrc" "gtk-application-prefer-dark-theme=1";
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
        PermitRootLogin = "yes";
      };
    };

    xserver.xkb.layout = "us";

    libinput.enable = true;

    logind.extraConfig = ''
      HandlePowerKey=ignore
    '';
  };

  environment = {
    systemPackages = with pkgs; [
      gnome.adwaita-icon-theme
      yubioath-flutter
      git
      wget
      libinput
    ];
    # could be useful:
    #etc."current-system-packages".text = let
    #  packages =
    #    builtins.map (p: "${p.name}") config.environment.systemPackages;
    #  sortedUnique = builtins.sort builtins.lessThan (lib.unique packages);
    #  formatted = builtins.concatStringsSep "\n" sortedUnique;
    #in formatted;
  };

  boot = {
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
    initrd.systemd.dbus.enable = true;
    loader = {
      systemd-boot.enable =
        if config.boot.lanzaboote.enable then lib.mkForce false else true;
      efi.canTouchEfiVariables = true;
    };
  };

  networking = {
    hostName = "${hostName}";
    networkmanager.enable = lib.mkDefault true;
  };

  nixpkgs = {
    config.allowUnfree = true;
    overlays = builtins.attrValues self.outputs.overlays;
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
      noto-fonts-cjk-sans
      noto-fonts-emoji
      liberation_ttf
      fira-code
      fira-code-symbols
      mplus-outline-fonts.githubRelease
      dina-font
      proggyfonts
      (nerdfonts.override { fonts = [ "FiraCode" ]; })
    ];
    fontconfig.defaultFonts = { monospace = [ "FiraCode Nerd Font Mono" ]; };
  };

  programs.zsh.enable = false;
  users.defaultUserShell = pkgs.bash;
  users.users.knoff = {
    initialPassword = "password";
    isNormalUser = true;
    shell = pkgs.bash;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" "dialout" ];
    openssh.authorizedKeys.keys = [ ];
  };

  users.users.root.openssh.authorizedKeys.keys = [ ];

  system.stateVersion = "23.11";
}
