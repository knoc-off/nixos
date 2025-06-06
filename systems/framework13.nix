{ lib, inputs, pkgs, self, hostname, user, config, ... }@args: {
  imports = [
    ./modules/minecraft.nix

    (self.nixosModules.home { inherit args; })

    inputs.disko.nixosModules.disko
    { disko.devices.disk.vdb.device = "/dev/nvme0n1"; }
    ./hardware/disks/btrfs-luks.nix

    # Hardware configs
    ./hardware/hardware-configuration.nix
    ./hardware/bluetooth.nix
    ./hardware/fingerprint

    inputs.hardware.nixosModules.framework-13-7040-amd

    {
      services.openvpn.servers = {
        # work-production = {
        #   config = ''
        #     config /etc/secrets/vpn/work/staging/production.ovpn
        #   '';
        #   autoStart = false;
        # };
        # work-staging = {
        #   config = ''
        #     config /etc/secrets/vpn/work/staging/staging.ovpn
        #     # cert /etc/secrets/vpn/work/staging/certificate.pem
        #     # key /etc/secrets/vpn/work/staging/key.pem
        #     ## If using PKCS12 instead, uncomment the line below and comment out cert/key lines
        #     # pkcs12 /etc/secrets/vpn/client-identity.p12
        #   '';
        #   autoStart = false;
        # };
      };
    }

    # {
    # let
    #
    #   kanataConfig = pkgs.writeText "kanata-german_override-config.kdb" ''
    #     ;; Global configuration: process unmapped keys.
    #     (defcfg process-unmapped-keys yes)
    #
    #     ;;; Define exactly one source of keys (defsrc).
    #     ;;; This uses a typical US QWERTY–like layout (approximate 60% keyboard).
    #     (defsrc
    #       grv    1    2    3    4    5    6    7    8    9    0    -    =    bspc
    #       tab    q    w    e    r    t    y    u    i    o    p    [    ]    \
    #       caps   a    s    d    f    g    h    j    k    l    ;    '    ret
    #       lsft   z    x    c    v    b    n    m    ,    .    /    rsft
    #       lctl   lmet lalt           spc            ralt rmet rctl
    #     )
    #
    #     ;;; Define aliases.
    #     ;;; remap the physical "caps" (from defsrc) → "cap" which outputs lmet (Super)
    #     ;;; and remap the physical ralt → "ralt-umlaut", which while held activates the umlaut layer.
    #     (defalias
    #       cap         lmet
    #       ralt-umlaut (layer-while-held umlaut)
    #     )
    #
    #     ;;; The default (base) layer.
    #     ;;; In this layer, the defsrc position for physical Caps outputs our alias @cap
    #     ;;; and the defsrc position for Right Alt outputs our alias @ralt-umlaut.
    #     (deflayer default
    #       grv    1    2    3    4    5    6    7    8    9    0    -    =    bspc
    #       tab    q    w    e    r    t    y    u    i    o    p    [    ]    \
    #       @cap   a    s    d    f    g    h    j    k    l    ;    '    ret
    #       lsft   z    x    c    v    b    n    m    ,    .    /    rsft
    #       lctl   lmet lalt           spc            @ralt-umlaut rmet rctl
    #     )
    #
    #     ;;; The umlaut layer.
    #     ;;; When this layer is active (by holding Right Alt), we override selected keys:
    #     ;;; • In row 2, the 8th key ("u") becomes "ü" and the 10th key ("o") becomes "ö".
    #     ;;; • In row 3, the 2nd key ("a") becomes "ä".
    #     ;;; All unspecified keys are transparent (using "_") and thus fall back to the lower layer.
    #     (deflayer umlaut
    #       ;; Row 1 (14 keys): pass-through.
    #       _ _ _ _ _ _ _ _ _ _ _ _ _ _
    #       ;; Row 2 (14 keys): override key 8 and key 10.
    #       tab  q   w   e   r   t   y   (unicode ü)   i   (unicode ö)   p   [   ]   \
    #       ;; Row 3 (13 keys): override the second key ("a") with "ä".
    #       _  (unicode ä)    _   _   _   _   _   _   _   _   _   _   _
    #       ;; Row 4 (12 keys): transparent.
    #       _ _ _ _ _ _ _ _ _ _ _ _
    #       ;; Row 5 (7 keys): transparent.
    #       _ _ _ _ _ _ _
    #     )
    #   '';
    #
    # in

    #   hardware.uinput.enable = true;

    #   services.kanata = {
    #     enable = false;
    #     package = pkgs.kanata;

    #     keyboards = {
    #       german_override = {
    #         # Let Kanata auto-detect keyboard devices.
    #         devices = [ ];
    #         # Remove the unsupported `--verbose` flag by keeping extraArgs empty.
    #         extraArgs = [ ];
    #         # Disable the TCP server by setting port to null.
    #         port = null;
    #         # Use the generated configuration file.
    #         configFile = kanataConfig;
    #         # These are unused when configFile is provided.
    #         config = "";
    #         extraDefCfg = "";
    #       };
    #     };
    #   };
    # }

    {
      networking.networkmanager.enable = lib.mkDefault true;

      console.keyMap = lib.mkDefault "us";

      programs = { dconf.enable = lib.mkDefault true; };

      services = {
        resolved.enable = lib.mkDefault true;
        fwupd.enable = lib.mkDefault true;
        openssh = {
          enable = lib.mkDefault true;
          settings.PermitRootLogin = lib.mkDefault "no";
        };
        xserver.xkb.layout = lib.mkDefault "us";
        printing.enable = lib.mkDefault true;
        avahi = {
          enable = lib.mkDefault true;
          nssmdns4 = lib.mkDefault true;
        };
        libinput.enable = lib.mkDefault true;
      };

      fonts = { enableDefaultPackages = lib.mkDefault true; };

      environment.systemPackages = lib.mkDefault (with pkgs; [
        # gnome.adwaita-icon-theme
        yubioath-flutter
        git
        wget
        libinput
      ]);

      time.timeZone = lib.mkDefault "Europe/Berlin";
      i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

    }

    # module to setup boot
    ./hardware/boot.nix

    # Sops. I think this could be some kind of module. to abstract the annoying parts of it.
    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/${hostname}/default.yaml;
        # This will automatically import SSH keys as age keys
        age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
        secrets."ANTHROPIC_API_KEY" = { mode = "0644"; };
      };
    }

    # Pipewire / Audio
    ./modules/audio

    # Nix package settings
    {

      nixpkgs.config.allowUnfree = true;
      nix = {
        registry = {
          nixpkgs.flake = inputs.nixpkgs;
          nixos-hardware.flake = inputs.hardware;
        };
        #nix.nixPath = [ "/etc/nix/path" ];
        #environment.etc."nix/path/nixpkgs".source = inputs.nixpkgs;
        nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
        settings = {
          substituters = [ "https://hyprland.cachix.org" ];
          trusted-public-keys = [
            "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
          ];
          experimental-features = [ "nix-command" "flakes" "pipe-operators" ];
          trusted-users = [ "@wheel" ];
        };
      };
    }

    # Window manager
    self.nixosModules.windowManager.hyprland

    {

      # services = {
      #   greetd = {
      #     enable = true;
      #     settings = {
      #       default_session = {
      #         command = "${pkgs.dwl}/bin/dwl -s kodi";
      #         #command = "${pkgs.bash}/bin/bash";
      #         inherit user;
      #       };
      #     };
      #   };
      #   seatd = {
      #     enable = true;
      #     inherit user;
      #   };
      # };

    }

    ./modules/shell/fish.nix

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

  programs = {
    virt-manager.enable = true;
    direnv = {
      enable = true;
      silent = true;
    };
  };

  virtualisation = {
    waydroid.enable = false;

    libvirtd = {
      enable = true;

      qemu.swtpm.enable = true;

    };
  };

  # ================ minecraft =============
  # services.minecraft-servers.servers = let
  #   commonOptions = {
  #     autoStart = false;
  #     jvmOpts = "-Xmx8G -Xms8G";
  #     enable = true;
  #     serverProperties = {
  #       server-port = 25565;
  #       difficulty = 2; # 0: peaceful, 1: easy, 2: normal, 3: hard
  #       motd = "minecraft";
  #       spawn-protection = 0;

  #       # Rcon configuration
  #       enable-rcon = true;
  #       "rcon.password" = "123"; # doesn't have to be secure, local only
  #       "rcon.port" = 25570;
  #     };
  #     symlinks = {
  #       "ops.json" = pkgs.writeTextFile {
  #         name = "ops.json";
  #         text = ''
  #           [
  #             {
  #               "uuid": "c9e17620-4cc1-4d83-a30a-ef320cc099e6",
  #               "name": "knoc_off",
  #               "level": 4,
  #               "bypassesplayerlimit": true
  #             }
  #           ]
  #         '';
  #       };
  #     };
  #   };
  # in {
  #   beez = commonOptions // { package = pkgs.fabricServers.fabric-1_21_1; };
  #   test = commonOptions // { package = pkgs.fabricServers.fabric-1_21_4; };
  # };
  # services.minecraft-server-suite = {
  #   enable = true;

  #   # Optional: Enable RCON support
  #   rcon.enable = true;

  #   # Optional: Enable Gate proxy
  #   gate = {
  #     enable = false;
  #     domain = "kobbl.co";
  #     customRoutes = [{
  #       host = "kobbl.co";
  #       backend = "localhost:25500";
  #     }];
  #   };
  # };
  # ================ minecraft =============

  security.sudo.extraRules = [{
    #groups = [ "networkmanager" ];
    users = [ user ];
    #groups = [ 1006 ];
    commands = [{
      command =
        "${pkgs.wgnord}/bin/wgnord"; # is this a security issue? its not writable
      options = [ "NOPASSWD" ];
    }];
  }];

  programs = {
    # not super needed.
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
    # udev.extraRules = ''
    #   # Auto decrypt and mount when device is plugged in
    #   ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_UUID}=="07133380-9f74-41e4-8b04-2b05fb3d94ab", \
    #   RUN+="${pkgs.cryptsetup}/bin/cryptsetup luksOpen --key-file /etc/secrets/drives/fa6b949.key $env{DEVNAME} fa6b949", \
    #   RUN+="${pkgs.toybox}/bin/mount /dev/mapper/fa6b949 /mnt/fa6b949"
    # '';

    udev.extraRules = ''
      # STMicroelectronics ST-LINK/V2
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="3748", MODE="0666", GROUP="users"
      # other programmers if needed, e.g., CH340/CH341 for some Arduinos
      SUBSYSTEM=="tty", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", MODE="0666", GROUP="users"
      KERNEL=="ttyUSB[0-9]*", MODE="0666", GROUP="users"
      KERNEL=="ttyACM[0-9]*", MODE="0666", GROUP="users"
    '';

  };

  # Create mount point directory, this needs to be changed maybe?
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

  programs.localsend.enable = true;
  networking = {
    hostName = hostname;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22000 38071 21027 53317 ];
      allowedUDPPorts = [ 22000 21027 38071 53317 ];
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
    type = "lanzaboote";
    efiSupport = true;
  };

  boot = {

    #kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

    # fingerpritn scanner does not work without this, suddenly. TODO: Try to remove this
    kernelParams = [ "usbcore.autosuspend=-1" ];
    kernel.sysctl = { "vm.swappiness" = 20; };
  };

  users = {
    users.${user} = {
      #shell = pkgs.fish;
      isNormalUser = lib.mkDefault true;
      extraGroups =
        [ # we should automate this. if networkmanager is enabled, then add it, etc.
          "wheel"
          "audio"
          "video"
          "dialout"
          "uinput"
          "lp"
        ] ++ (if config.virtualisation.libvirtd.enable then
          [ "libvirtd" ]
        else
          [ ]) ++ (if config.networking.networkmanager.enable then
            [ "networkmanager" ]
          else
            [ ]);
      initialPassword = "password";
      openssh.authorizedKeys.keys = [ ];
    };
  };

  system.stateVersion = "23.11";
}
