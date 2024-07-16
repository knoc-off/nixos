# im going to try to document as i go, with comments.
# each setting that is not super obvious should have, what impact it has, and why.
# for example enabling 32bit support for opengl, is needed for steam.
{
  lib,
  inputs,
  config,
  pkgs,
  outputs,
  ...
}: {
  imports = [
    # hardware configs
    ./hardware/hardware-configuration.nix
    ./hardware/bluetooth.nix
    ./hardware/fingerprint

    # lanzaboot

    # Sops
    inputs.sops-nix.nixosModules.sops
    {
      sops.defaultSopsFile = ./secrets/framework13/default.yaml;
      # This will automatically import SSH keys as age keys
      sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    }

    # pipewire / Audio
    ./modules/audio

    # nix package settings
    ./modules/nix.nix

    # Window manager
    ./modules/hyprland

    # run with the fish function nixcommit
    # This is an 'auto generated' file that should add a message to the build versions in the boot menu
    ./commit-message.nix

    # Android emulation
    #./modules/virtualisation/waydroid.nix
    ./modules/gtk
  ];

  services.flatpak.enable = true;

  programs.steam.enable = true;
  programs.steam.package = pkgs.steam-scaling;

  # Yubikey
  services.yubikey-agent.enable = true;
  services.pcscd.enable = true;
  services.udev.packages = [pkgs.yubikey-personalization];
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  # Fix wg-quick?
  services.resolved.enable = true;
  boot.initrd.systemd.dbus.enable = true;

  # Lets you run binaries.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      SDL2
      SDL2_image
      libz
    ];
  };

  # Custom module, that combines settings and theme
  services.gtkThemeSymlinks = {
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

  # exports all packages to a file in /etc.
  environment.etc."current-system-packages".text = let
    packages = builtins.map (p: "${p.name}") config.environment.systemPackages;
    sortedUnique = builtins.sort builtins.lessThan (lib.unique packages);
    formatted = builtins.concatStringsSep "\n" sortedUnique;
  in
    formatted;

  # Latest Kernel Version
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Attempt to fix the: GLib-GIO-ERROR**: No GSettings schemas are installed on the system
  programs.dconf.enable = true;
  services.fwupd.enable = true;

  networking.hostName = "framework"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # TODO: move to nix configs
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = builtins.attrValues outputs.overlays;

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  # Console
  console = {
    #font = "Lat2-Terminus16";
    packages = with pkgs; [terminus_font];
    #font = "${pkgs.terminus_fonts}/share/consolefonts/ter-u28n.psf.gz";
    font = "${pkgs.terminus_font}/share/consolefonts/ter-i22b.psf.gz";
    keyMap = lib.mkDefault "us";
    useXkbConfig = true; # use xkbOptions in tty.
  };

  # fonts
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    mplus-outline-fonts.githubRelease
    dina-font
    proggyfonts
    (nerdfonts.override {fonts = ["FiraCode"];})
  ];

  fonts = {
    enableDefaultPackages = true;

    fontconfig = {
      defaultFonts = {
        monospace = ["FiraCode Nerd Font Mono"];
      };
    };
  };

  # ssh
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PermitRootLogin = "no";
  };

  # Configure keymap in X11
  services.xserver.xkb.layout = "us";

  # Enable the CUPS printing service
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      hplip # Example driver for HP printers
      gutenprint # Drivers for a wide range of printers
      foo2zjs # Drivers for ZJStream protocol printers (e.g., some HP LaserJets)
    ];
  };

  # Optionally, enable Avahi for network printer discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
  };

  # needed for steam, and some other apps/games.
  hardware.opengl.driSupport32Bit = true;
  hardware.opengl.enable = true;
  hardware.pulseaudio.support32Bit = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.libinput.enable = true;

  # TODO: I could move my user to its own module, then import it to each system
  # Shells
  programs = {
    zsh.enable = false;
    fish.enable = true;
  };

  # should move this user to its own file, so i can import it where it makes sense
  users.users.knoff = {
    isNormalUser = true;
    #shell = lib.mkIf (config.programs.fish.enable) pkgs.fish
    #   (lib.mkIf (config.programs.zsh.enable) pkgs.zsh pkgs.bash);

    shell =
      if config.programs.fish.enable
      then pkgs.fish
      else if config.programs.zsh.enable
      then pkgs.zsh
      else pkgs.bash;
    extraGroups = ["wheel" "networkmanager" "audio" "video"];
    hashedPassword = "$y$j9T$jtFWvdQ6ghoncJ8srfdQn0$JN8OSftIfzHQmSpIZqeQyeK/Nrb8OQCbET5x2n82Yr9";
    openssh.authorizedKeys.keys = [
    ];
  };
  users.users.root.openssh.authorizedKeys.keys = [
  ];

  environment.systemPackages = with pkgs; [
    gnome.adwaita-icon-theme
    yubioath-flutter
    git
    wget
    home-manager # bootstrap
    libinput
  ];

  # don’t shutdown when power button is short-pressed
  services.logind.extraConfig = ''
    HandlePowerKey=lock
  '';

  # Open ports in the firewall. dont need any on this machine
  #networking.firewall.allowedTCPPorts = [ 22 80 433 3000 ];
  #networking.firewall.allowedUDPPorts = [ 22 80 433 3000 ];

  system.stateVersion = "23.11";
}
