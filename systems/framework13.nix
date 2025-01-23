{ lib, inputs, config, pkgs, self, system, outputs, theme, colorLib, hostname
, user, ... }: {
  imports = [
    #self.nixosModules.knoff

    ./modules/minecraft.nix

    { # Home-Manager
      imports = [ inputs.home-manager.nixosModules.home-manager ];

      home-manager = {
        useGlobalPkgs = false;
        useUserPackages = true;
        users.${user} = import ../home/knoff-laptop.nix;
        extraSpecialArgs = {
          inherit inputs outputs self theme colorLib hostname system user;
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
    # temp fix with kmod issues
    {
      hardware = {
        # disable framework kernel module
        # https://github.com/NixOS/nixos-hardware/issues/1330
        framework.enableKmod = false;
      };
    }

    #misc settings that i usually use.
    ./modules/misc.nix

    # module to setup boot
    ./hardware/boot.nix

    ./modules/wpad.nix

    # Sops
    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/framework13/default.yaml;
        # This will automatically import SSH keys as age keys
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
        secrets."ANTHROPIC_API_KEY" = { mode = "0644"; };
      };
    }

    # Pipewire / Audio
    ./modules/audio

    # Nix package settings
    ./modules/nix.nix

    # Window manager
    self.nixosModules.windowManager.hyprland
    self.nixosModules.desktop.totem # media player

    # Android emulation
    #./modules/virtualisation/waydroid.nix

    # enable bash shell customizations
    ./modules/shell/bash.nix

    #./modules/yubikey.nix
  ];

  # create a service to run at startup each boot. run wgnord c de to connect to the vpn
  # systemd.services.wgnord = {
  #   description = "WireGuard NordVPN";
  #   after = [ "network.target" ];
  #   wantedBy = [ "multi-user.target" ];
  #   serviceConfig = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.wgnord}/bin/wgnord c de";
  #   };
  # };


  programs.direnv = {
    enable = true;
    silent = true;
  };

  services.minecraft-server-suite = {
    enable = true;

    # Optional: Enable RCON support
    rcon.enable = true;

    # Optional: Enable Gate proxy
    gate = {
      enable = false;
      domain = "kobbl.co";
      customRoutes = [{
        host = "kobbl.co";
        backend = "localhost:25500";
      }];
    };
  };

  virtualisation = {
    waydroid.enable = false;

    libvirtd = {
      enable = true;

      qemu.swtpm.enable = true;

    };
  };
  programs.virt-manager.enable = true;

  services.minecraft-servers.servers = let
    commonOptions = {
      autoStart = false;
      jvmOpts = "-Xmx8G -Xms8G";
      enable = true;
      serverProperties = {
        server-port = 25565;
        difficulty = 2; # 0: peaceful, 1: easy, 2: normal, 3: hard
        motd = "minecraft";
        spawn-protection = 0;

        # Rcon configuration
        enable-rcon = true;
        "rcon.password" = "123"; # doesn't have to be secure, local only
        "rcon.port" = 25570;
      };
      symlinks = {
        "ops.json" = pkgs.writeTextFile {
          name = "ops.json";
          text = ''
            [
              {
                "uuid": "c9e17620-4cc1-4d83-a30a-ef320cc099e6",
                "name": "knoc_off",
                "level": 4,
                "bypassesplayerlimit": true
              }
            ]
          '';
        };
      };
    };
  in {
    beez = commonOptions // { package = pkgs.fabricServers.fabric-1_21_1; };
    test = commonOptions // { package = pkgs.fabricServers.fabric-1_21_4; };
  };

  security.sudo.extraRules = [{
    #groups = [ "networkmanager" ];
    users = [ "${user}" ]; # ? auto
    #groups = [ 1006 ];
    commands = [{
      command =
        "${pkgs.wgnord}/bin/wgnord"; # is this a security issue? its not writable
      options = [ "NOPASSWD" ];
    }];
  }];

  programs = {
    nix-ld = {
      enable = true;
      libraries = with pkgs; [ stdenv.cc.cc SDL2 SDL2_image libz ];
    };
    dconf.enable = true;
  };

  programs.steam.enable = true;
  services = {
    gvfs.enable = true;
    devmon.enable = true;
    udisks2.enable = true;
    upower.enable = true;
    accounts-daemon.enable = true;

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

    # Add udev rules for auto-mounting and launching Nemo
    udev.extraRules = ''

      # Auto decrypt and mount when device is plugged in
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="07133380-9f74-41e4-8b04-2b05fb3d94ab", \
      RUN+="${pkgs.cryptsetup}/bin/cryptsetup luksOpen --key-file /etc/secrets/drives/fa6b949.key $env{DEVNAME} fa6b949", \
      RUN+="${pkgs.toybox}/bin/mount /dev/mapper/fa6b949 /mnt/fa6b949"

    '';

  };

    # Create mount point directory
  system.activationScripts = {
    createMountPoint = {
      text = ''
        mkdir -p /mnt/fa6b949
      '';
    };
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
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22000 38071 ];
      allowedUDPPorts = [ 21027 ];
      #extraCommands = ''
      #  iptables -A INPUT -p tcp --dport 22000 -s niko.ink -j ACCEPT
      #  iptables -A INPUT -p udp --dport 21027 -s niko.ink -j ACCEPT
      #'';
    };
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

  # Set default values for the new options
  bootloader = {
    type = "lanzaboote"; # Default to systemd-boot as in the original config
    efiSupport = true; # Enable EFI support by default
  };

  boot = {
    kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

    # fingerpritn scanner does not work without this, suddenly.
    kernelParams = [ "usbcore.autosuspend=-1" ];
    kernel.sysctl = { "vm.swappiness" = 20;};
  };

  users = {
    users.${user} = {
      isNormalUser = lib.mkDefault true;
      extraGroups =
        [ "wheel" "networkmanager" "audio" "video" "dialout" "libvirtd" ];
      initialPassword = "password";
      openssh.authorizedKeys.keys = [ ];
    };
  };

  system.stateVersion = "23.11";
}
