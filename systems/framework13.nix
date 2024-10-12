{ lib, inputs, config, pkgs, self, system, outputs, theme, colorLib, hostname,   ... }: {
  imports = [
    #self.nixosModules.knoff

    { # Home-Manager
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = false;
        useUserPackages = true;
        users.knoff = import ../home/knoff-laptop.nix;
        extraSpecialArgs = {
          inherit inputs outputs self theme colorLib hostname system;
        };
      };
    }

    #inputs.nixos-cli.nixosModules.nixos-cli
    #{
    #  # Enable the nixos-cli service
    #  services.nixos-cli = {
    #    enable = true;
    #  };
    #}

    inputs.hardware.nixosModules.framework-13-7040-amd

    inputs.disko.nixosModules.disko
    { disko.devices.disk.vdb.device = "/dev/nvme0n1"; }
    ./hardware/disks/btrfs-luks.nix

    # Hardware configs
    ./hardware/hardware-configuration.nix
    ./hardware/bluetooth.nix
    ./hardware/fingerprint

    #misc settings that i usually use.
    ./modules/misc.nix

    # module to setup boot
    ./hardware/boot.nix



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
    self.nixosModules.windowManager.hyprland
    #./modules/hyprland

    # Android emulation
    #./modules/virtualisation/waydroid.nix

    # enable bash shell customizations
    ./modules/shell/bash.nix

    #./modules/yubikey.nix
  ];



  programs = {
    nix-ld = {
      enable = true;
      libraries = with pkgs; [ stdenv.cc.cc SDL2 SDL2_image libz ];
    };
    dconf.enable = true;
  };

  services = {
    # Pretty much just needed this for Steam
    flatpak.enable = true;

    # Fix wg-quick?
    resolved.enable = true;

    fwupd.enable = true;

    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = lib.mkDefault "no";
      };
    };

    xserver.xkb.layout = "us";

    printing = {
      enable = true;
      drivers = with pkgs; [ hplip gutenprint foo2zjs ];
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

  #environment = {
  #  etc."current-system-packages".text = let
  #    packages =
  #      builtins.map (p: "${p.name}") config.environment.systemPackages;
  #    sortedUnique = builtins.sort builtins.lessThan (lib.unique packages);
  #    formatted = builtins.concatStringsSep "\n" sortedUnique;
  #  in formatted;
  #};

  networking = {
    hostName = hostname;
  };

  console = {
    packages = with pkgs; [ terminus_font ];
    font = "${pkgs.terminus_font}/share/consolefonts/ter-i22b.psf.gz";
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
    fontconfig.defaultFonts = { monospace = [ "FiraCode Nerd Font Mono" ]; };
  };

  # Set default values for the new options
  bootloader = {
    type = "lanzaboote";  # Default to systemd-boot as in the original config
    efiSupport = true;  # Enable EFI support by default
  };

  boot = {
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

    # fingerpritn scanner does not work without this, suddenly.
    kernelParams = [ "usbcore.autosuspend=-1" ];
  };

  users = {
    users.knoff = {
      isNormalUser = lib.mkDefault true;
      extraGroups = [ "wheel" "networkmanager" "audio" "video" "dialout" ];
      initialPassword = "password";
      openssh.authorizedKeys.keys = [ ];
    };
  };

  system.stateVersion = "23.11";
}
