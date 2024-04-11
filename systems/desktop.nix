# im going to try to document as i go, with comments.
# each setting that is not super obvious should have, what impact it has, and why.
# for example enabling 32bit support for opengl, is needed for steam.
{ lib
, inputs
, config
, pkgs
, outputs
, ...
}: {
  imports = [


    inputs.hardware.nixosModules.common-cpu-amd
    inputs.hardware.nixosModules.common-gpu-amd
    inputs.hardware.nixosModules.common-pc-ssd

    # hardware configs
    ./hardware/hardware-configuration.nix
    ./hardware/bluetooth.nix

    # Disko
    ./hardware/disks/btrfs-luks.nix

    # Secure boot
    inputs.lanzaboote.nixosModules.lanzaboote
    # https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md

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
  ];

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [

      # Dwarf Fortress
      stdenv.cc.cc
      SDL2
      SDL2_image
      ## DFHACK
      libz

    ];
  };

  environment.etc =
    let
      themeName = "Fluent-Dark";
      themePkg = pkgs.fluent-gtk-theme;
    in
    {
      "xdg/gtk-2.0".source = "${themePkg}/share/themes/${themeName}/gtk-2.0";
      "xdg/gtk-3.0".source = "${themePkg}/share/themes/${themeName}/gtk-3.0";


      #"xdg/gtk-2.0/gtkrc".text = "gtk-application-prefer-dark-theme=1";
      #"xdg/gtk-3.0/settings.ini".text = ''
      #  [Settings]
      #  gtk-application-prefer-dark-theme=1
      #  gtk-error-bell=false
      #'';
      #"xdg/gtk-4.0/settings.ini".text = ''
      #  [Settings]
      #  gtk-application-prefer-dark-theme=1
      #  gtk-error-bell=false
      #'';

    };

  # Use the latest linux kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Attempt to fix the: GLib-GIO-ERROR**: No GSettings schemas are installed on the system
  programs.dconf.enable = true;
  services.fwupd.enable = true;

  # Use the systemd-boot EFI boot loader.
  # disable if using lanzaboote
  boot.loader.systemd-boot.enable = (if config.boot.lanzaboote.enable then lib.mkForce false else true);

  boot.loader.efi.canTouchEfiVariables = true;
  boot.lanzaboote = {
    enable = false;
    pkiBundle = "/etc/secureboot";
  };

  networking.hostName = "desktop"; # Define your hostname.
  networking.networkmanager.enable = true;

  # this allows running flatpaks.
  services.flatpak.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Berlin";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = builtins.attrValues outputs.overlays;

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    #font = "Lat2-Terminus16";
    packages = with pkgs; [ terminus_font ];
    #font = "${pkgs.terminus_fonts}/share/consolefonts/ter-u28n.psf.gz";
    font = "${pkgs.terminus_font}/share/consolefonts/ter-i22b.psf.gz";
    keyMap = lib.mkDefault "us";
    useXkbConfig = true; # use xkbOptions in tty.
  };

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
    (nerdfonts.override { fonts = [ "FiraCode" ]; })
  ];

  fonts = {
    enableDefaultPackages = true;

    fontconfig = {
      defaultFonts = {
        monospace = [ "FiraCode Nerd Font Mono" ];
      };
    };
  };

  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    #settings.PermitRootLogin = "no";
  };

  # Configure keymap in X11
  #services.xserver.layout = "us";
  services.xserver.xkb.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e,caps:escape";

  #hardware.opengl.driSupport32Bit = true;
  hardware.opengl.driSupport32Bit = true;
  hardware.opengl.enable = true;
  hardware.pulseaudio.support32Bit = true;

  # Shells
  programs = {
    zsh.enable = false;
    fish.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.knoff = {
    isNormalUser = true;
    shell =
      if config.programs.fish.enable
        then pkgs.fish
      else if config.programs.zsh.enable
        then pkgs.zsh
      else pkgs.bash;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    initialPassword = "password";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink" # laptop
    ];
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink" # laptop
  ];

  environment.systemPackages = with pkgs; [
    # TODO: see if this fixes issues
    gnome.adwaita-icon-theme

    #vulkan-tools

    # misc tools
    git
    wget
    libinput
  ];

  services.logind.extraConfig = ''
    # don’t shutdown when power button is short-pressed
    HandlePowerKey=suspend
  '';

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 22 80 433 3000 ];
  networking.firewall.allowedUDPPorts = [ 22 80 433 3000 ];

  system.stateVersion = "23.11";
}
