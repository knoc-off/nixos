{
  lib,
  inputs,
  pkgs,
  self,
  config,
  hostname,
  ...
}: let
  user = "knoff";
in {
  imports = [
    # inputs.nixgl.packages.x86_64-linux.nixGLIntel

    inputs.determinate.nixosModules.default

    self.nixosModules.tailnet
    {
      # Laptop client: enroll declaratively and keep MagicDNS on.
      services.tailnet = {
        enable = true;
        acceptDns = true;
      };
    }

    self.nixosModules.users.knoff
    self.nixosModules.nix
    self.nixosModules.nh
    self.nixosModules.pipewire

    self.nixosModules.misc
    self.nixosModules.console

    inputs.disko.nixosModules.disko
    {disko.devices.disk.vdb.device = "/dev/nvme0n1";}

    ./hardware/disks/btrfs-luks.nix

    ./hardware/hardware-configuration.nix
    ./hardware/bluetooth.nix
    ./hardware/fingerprint

    self.nixosModules.hyprland
    self.nixosModules.noctalia

    inputs.hardware.nixosModules.framework-13-7040-amd
    {
      hardware.uinput.enable = true;
    }

    {
      # services.ivpn.enable = true;
      services.mullvad-vpn.enable = true;
    }

    self.nixosModules.lspmux
    {services.lspmux.enable = true;}

    ./hardware/boot.nix

    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/${hostname}/default.yaml;
        age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
        secrets."shell_environment/OPENROUTER_API_KEY" = {
          mode = "0644";
        };
      };
    }

    {
      nixpkgs.config.allowUnfree = true;
      nix = {
        registry = {
          nixpkgs.flake = inputs.nixpkgs;
          nixos-hardware.flake = inputs.hardware;
        };
        nixPath = ["nixpkgs=${inputs.nixpkgs}"];
      };
    }

    {
      services.greetd = let
        tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
      in {
        enable = true;
        settings = {
          default_session = {
            command = "${tuigreet} --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'";
            user = "greeter";
          };
        };
      };
    }

    self.nixosModules.fish

    #./modules/yubikey.nix
  ];

  programs = {
    virt-manager.enable = true; # needed for what?
    direnv = {
      enable = true;
      silent = true;
    };
  };

  virtualisation = {
    libvirtd = {
      enable = true;

      qemu.swtpm.enable = true;
    };
  };

  programs = {
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        libxcursor
        xorg.libXrandr
        libx11
        libGL
        stdenv.cc.cc
        SDL2
        SDL2_image
        libz
      ];
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

    logind.settings.Login = {
      HandleLidSwitch = "suspend";
      HandlePowerKey = "suspend";
    };

    # flatpak.enable = true;

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

    xserver.xkb = {
      layout = "us";
      # Kanata owns the physical Caps key (remapped to rmet+layer).
      # This makes the Caps_Lock *keysym* a no-op at the XKB layer,
      # so stray Caps_Lock events from wtype/VMs/remote apps can
      # never latch the lock state. Shift+Caps etc. also can't toggle it.
      options = "caps:none";
    };

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

    udev.extraRules = ''
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0483", ATTRS{idProduct}=="3748", MODE="0666"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="7523", MODE="0666"
      SUBSYSTEM=="usb", ATTRS{idVendor}=="1a86", ATTRS{idProduct}=="5523", MODE="0666"

      KERNEL=="uinput", MODE="0660", GROUP="uinput", OPTIONS+="static_node=uinput"
    '';
  };

  programs.localsend.enable = true;

  networking = {
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22000
        38071
        21027
        53317
      ];
      allowedUDPPorts = [
        22000
        21027
        38071
        53317
      ];
      #extraCommands = ''
      #  iptables -A INPUT -p tcp --dport 22000 -s niko.ink -j ACCEPT
      #  iptables -A INPUT -p udp --dport 21027 -s niko.ink -j ACCEPT
      #'';
    };
  };

  console = {
    packages = with pkgs; [terminus_font];
    font = "${pkgs.terminus_font}/share/consolefonts/ter-i22b.psf.gz";
    useXkbConfig = true;
  };

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
      fira-code
      fira-code-symbols
      mplus-outline-fonts.githubRelease
      dina-font
      proggyfonts
      pkgs.nerd-fonts.fira-code
    ];
    fontconfig.defaultFonts = {
      monospace = ["FiraCode Nerd Font Mono"];
    };
  };

  bootloader = {
    type = "lanzaboote";
    efiSupport = true;
  };

  boot = {
    binfmt.emulatedSystems = ["aarch64-linux"];
    kernelParams = ["usbcore.autosuspend=-1"];
    kernel.sysctl = {
      # zram is RAM-speed, so be eager to use it before reclaiming caches.
      # The disk swapfile stays as a low-priority overflow only.
      "vm.swappiness" = 150;
      # Increase inotify limits for rust-analyzer and other file watchers
      "fs.inotify.max_user_watches" = 524288;
      "fs.inotify.max_user_instances" = 1024;
    };
  };

  # Compressed in-RAM swap. zstd compresses typical app memory ~3:1 at
  # RAM speed, which absorbs pressure spikes without thrashing the slow
  # btrfs disk swapfile (kept as a lower-priority overflow).
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    priority = 100;
  };

  users = {
    users.${user} = {
      shell = pkgs.fish;
      isNormalUser = lib.mkDefault true;
      extraGroups =
        [
          "wheel"
          "audio"
          "video"
          "dialout"
          "uinput"
          "input"
          "lp"
        ]
        ++ (
          if config.virtualisation.libvirtd.enable
          then ["libvirtd"]
          else []
        )
        ++ (
          if config.networking.networkmanager.enable
          then ["networkmanager"]
          else []
        );
      initialPassword = "password";
      openssh.authorizedKeys.keys = [];
    };
  };

  system.stateVersion = "23.11";
}
