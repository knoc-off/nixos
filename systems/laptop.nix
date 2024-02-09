# im going to try to document as i go, with comments.
# each setting that is not super obvious should have, what impact it has, and why.
# for example enabling 32bit support for opengl, is needed for steam.

{ lib, inputs, config, pkgs, outputs, ... }:

{
  imports =
    [
      # hardware configs
      ./hardware/hardware-configuration.nix

      # Disko
      ./hardware/disks/btrfs-luks.nix

      # hardware for my laptop
      inputs.hardware.nixosModules.framework-13-7040-amd
      ./hardware/fingerprint

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

  # IDK if this does anything, TODO: check
  # doesent seem to do much, cant remember why i added it.
  environment.etc = {
    "xdg/gtk-2.0".source = "${pkgs.orchis-theme}/share/themes/Orchis-Grey-Dark/gtk-2.0";
    "xdg/gtk-3.0".source = "${pkgs.orchis-theme}/share/themes/Orchis-Grey-Dark/gtk-3.0";
  };





  # Attempt to fix the: GLib-GIO-ERROR**: No GSettings schemas are installed on the system
  programs.dconf.enable = true;

  #environment.systemPackages = [
  #  pkgs.gnome.adwaita-icon-theme
  #];


  services.fwupd.enable = true;


  # Use the systemd-boot EFI boot loader.
  # disable if using lanzaboote
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/etc/secureboot";
  };


  networking.hostName = "framework"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # this allows running flatpaks.
  services.flatpak.enable = true;

  # enable power management, improves battery life.
  #powerManagement.powertop.enable = true;

  # power profiles.
  #services.power-profiles-daemon.enable = true;
  # thermal management. TODO: check if this is needed.
  #services.thermald.enable = true;
  services.auto-cpufreq = {
    enable = true;
    settings = {
      battery = {
        governor = "conservative";
        turbo = "auto";
      };
      charger = {
        governor = "ondemand";
        turbo = "auto";
      };
    };
  };
  #  services.tlp = {
  #    enable = true;
  #    settings = {
  #      CPU_SCALING_GOVERNOR_ON_AC = "performance";
  #      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
  #
  #      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
  #      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
  #
  #      CPU_MIN_PERF_ON_AC = 0;
  #      CPU_MAX_PERF_ON_AC = 100;
  #      CPU_MIN_PERF_ON_BAT = 0;
  #      CPU_MAX_PERF_ON_BAT = 20;
  #
  #      #Optional helps save long term battery health
  #      START_CHARGE_THRESH_BAT0 = 40; # 40 and bellow it starts to charge
  #      STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging
  #
  #    };
  #  };

  # Set your time zone.
  time.timeZone = "Europe/Berlin";
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = builtins.attrValues outputs.overlays;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

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

  # Enable the X11 windowing system.
  # services.xserver.enable = true;
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PermitRootLogin = "yes";
  };


  # Configure keymap in X11
  #services.xserver.layout = "us";
  services.xserver.xkb.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;


  # needed for steam, and some other apps/games.
  # steam benifits from launch param: -forcedesktopscaling 1.0%U
  # NIXPKGS_ALLOW_UNFREE=1 nix run nixpkgs#steam --impure -- -forcedesktopscaling 1.0%U
  hardware.opengl.driSupport32Bit = true; # For 32 bit applications

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput.enable = true;

  programs.zsh.enable = false;
  programs.fish.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.knoff = {
    isNormalUser = true;
    #shell = lib.mkIf (config.programs.fish.enable) pkgs.fish
    #   (lib.mkIf (config.programs.zsh.enable) pkgs.zsh pkgs.bash);

    shell =
      if config.programs.fish.enable then pkgs.fish
      else if config.programs.zsh.enable then pkgs.zsh
      else pkgs.bash;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    initialPassword = "password";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCzcqPB9VHe3vEaLRHEjtk39Y0cLIzl4MoInoMOIlHR3SmaNfaSYon64UGHydcTSoYusawKN+re+OPNHB/o04j7kW7Gfn3BDVzcwv2jADKmddC9fnhNz7YYC0S2aWMkvbXgzUmiQ3vC/g71xPYULKUBB0ZNKwV8DUjP/85Ft5I4CAfdcnss4410iVmWScLcmgZWHJgT0q0IAvdBQowMyJm5UIRINgZxOSOroEwgTFY74WNy/CKfx7/kDTte6OEgKwud99GhoA4o7up3GRXMPdFEut2af9iimIC7XyVRsTmQju1Jv1rf7KItRzAXGPYBNCz030Ak9bI1y8QwMYa1E/ZcnHXihdvAeEaJsUUPw9hmKOtNAtMnY42tRE4d+ihehZSKRhpXAUSoqdMvjCRNg2QjDvnv98GrAa7Mcbg7n5scCjuoczvaQ7cOAOGAYqLHLSBl9wqxUk9dZo0oTW/5NkHpslRNEy25biBqJukJAylLNXcB0YdnlTYDTcnyGtj9TIk= knoff"
    ];
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCzcqPB9VHe3vEaLRHEjtk39Y0cLIzl4MoInoMOIlHR3SmaNfaSYon64UGHydcTSoYusawKN+re+OPNHB/o04j7kW7Gfn3BDVzcwv2jADKmddC9fnhNz7YYC0S2aWMkvbXgzUmiQ3vC/g71xPYULKUBB0ZNKwV8DUjP/85Ft5I4CAfdcnss4410iVmWScLcmgZWHJgT0q0IAvdBQowMyJm5UIRINgZxOSOroEwgTFY74WNy/CKfx7/kDTte6OEgKwud99GhoA4o7up3GRXMPdFEut2af9iimIC7XyVRsTmQju1Jv1rf7KItRzAXGPYBNCz030Ak9bI1y8QwMYa1E/ZcnHXihdvAeEaJsUUPw9hmKOtNAtMnY42tRE4d+ihehZSKRhpXAUSoqdMvjCRNg2QjDvnv98GrAa7Mcbg7n5scCjuoczvaQ7cOAOGAYqLHLSBl9wqxUk9dZo0oTW/5NkHpslRNEy25biBqJukJAylLNXcB0YdnlTYDTcnyGtj9TIk= knoff"
  ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # TODO: see if this fixes issues
    gnome.adwaita-icon-theme

    # misc tools
    git
    wget
    home-manager # bootstrap
    libinput
  ];

  services.logind.extraConfig = ''
    # don’t shutdown when power button is short-pressed
    HandlePowerKey=suspend
  '';

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:





  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.allowedUDPPorts = [ 22 ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}
