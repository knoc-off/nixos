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
    # hardware configs
    ./hardware/hardware-configuration.nix
    ./hardware/bluetooth.nix
    ./hardware/fingerprint


    # Sops
    inputs.sops-nix.nixosModules.sops
    {
      sops.defaultSopsFile = ./secrets/framework13/default.yaml;
      # This will automatically import SSH keys as age keys
      sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];

      sops.secrets."hashedpassword" = {};
      sops.secrets."hashedpassword".owner = config.users.users.knoff.name;
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

  #qt.style = "gtk2";
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

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Attempt to fix the: GLib-GIO-ERROR**: No GSettings schemas are installed on the system
  programs.dconf.enable = true;
  services.fwupd.enable = true;

  # Use the systemd-boot EFI boot loader.
  # disable if using lanzaboote
  boot.loader.systemd-boot.enable = (if config.boot.lanzaboote.enable then lib.mkForce false else true);
  boot.loader.efi.canTouchEfiVariables = true;


  networking.hostName = "framework"; # Define your hostname.
  networking.networkmanager.enable = true; # Easiest to use and most distros use this by default.

  # this allows running flatpaks. i never use this.
  # services.flatpak.enable = true;

  # ---------------- Power
  #services.power-profiles-daemon.enable = false;
  # services.tlp = {
  #   enable = true;
  #   settings = {
  #     CPU_SCALING_GOVERNOR_ON_AC = "performance";
  #     CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
  #     CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
  #     CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
  #     CPU_MIN_PERF_ON_AC = 0;
  #     CPU_MAX_PERF_ON_AC = 100;
  #     CPU_MIN_PERF_ON_BAT = 0;
  #     CPU_MAX_PERF_ON_BAT = 30;
  #     #
  #     #      #Optional helps save long term battery health
  #     #      START_CHARGE_THRESH_BAT0 = 40; # 40 and bellow it starts to charge
  #     #      STOP_CHARGE_THRESH_BAT0 = 80; # 80 and above it stops charging
  #     #
  #   };
  # };

  # TODO: move to nix configs
  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = builtins.attrValues outputs.overlays;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Set your time zone.
  time.timeZone = "Europe/Berlin";
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
    settings.PermitRootLogin = "no";
  };

  # Configure keymap in X11
  services.xserver.xkb.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # needed for steam, and some other apps/games.
  hardware.opengl.driSupport32Bit = true;
  hardware.opengl.enable = true;
  hardware.pulseaudio.support32Bit = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput.enable = true;


  # TODO: I could move my user to its own module, then import it to each system
  # Shells
  programs = {
    zsh.enable = false;
    fish.enable = true;
  };
  # Define a user account. Don't forget to set a password with ‘passwd’.
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
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    hashedPasswordFile = config.sops.secrets."hashedpassword".path;
    openssh.authorizedKeys.keys = [
    ];
  };
  users.users.root.openssh.authorizedKeys.keys = [
  ];

  # List packages installed in system profile. To search, run:
  # $ nix search nixpkgs#wget
  environment.systemPackages = with pkgs; [
    # TODO: see if this fixes issues. somewhat
    gnome.adwaita-icon-theme

    #vulkan-tools

    # misc tools
    git
    wget
    home-manager # bootstrap
    libinput
  ];

  # don’t shutdown when power button is short-pressed
  services.logind.extraConfig = ''
    HandlePowerKey=suspend
  '';

  # Open ports in the firewall. dont need any on this machine
  #networking.firewall.allowedTCPPorts = [ 22 80 433 3000 ];
  #networking.firewall.allowedUDPPorts = [ 22 80 433 3000 ];

  system.stateVersion = "23.11";
}
