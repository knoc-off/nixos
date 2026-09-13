{
  lib,
  inputs,
  pkgs,
  self,
  config,
  hostname,
  ...
}:
let
  user = "knoff";
in
{
  imports = [
    # inputs.nixgl.packages.x86_64-linux.nixGLIntel

    self.nixosModules.tailnet
    {
      # Laptop client: enroll declaratively and keep MagicDNS on.
      services.tailnet = {
        enable = true;
        acceptDns = true;
      };
    }

    self.nixosModules.nix-cache
    {
      services.nixCache.leaf.enable = true;
    }

    self.nixosModules.users.knoff
    self.nixosModules.nix
    self.nixosModules.nh
    self.nixosModules.pipewire

    self.nixosModules.misc
    self.nixosModules.console

    self.nixosModules.btrfs-luks
    {
      disks.btrfsLuks = {
        enable = true;
        device = "/dev/nvme0n1";
        # Kept as "vdb" rather than the module default: renaming the disko
        # attribute would rewrite the generated device aliases on an
        # already-installed machine for no benefit.
        diskName = "vdb";
        swapSize = "32G";
      };
    }

    ./hardware-configuration.nix
    self.nixosModules.bluetooth
    self.nixosModules.fingerprint

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
    { services.lspmux.enable = true; }

    self.nixosModules.boot

    self.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets.yaml;
        secrets = {
          "shell_environment/OPENROUTER_API_KEY".owner = "knoff";
          "shell_environment/RHIZOME_TOKEN" = {
            owner = "knoff";
            sopsFile = ../../modules/shared-secrets.yaml;
          };
        };
      };
    }

    {
      services.greetd =
        let
          tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
        in
        {
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

  environment.systemPackages = with pkgs; [
    moreutils
  ];

  programs = {
    virt-manager.enable = true; # GUI frontend for libvirtd VMs below
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
        libxrandr
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

    flatpak.enable = true;

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

    # brightnessctl ships its own udev rule granting the `video` group write
    # access to backlight sysfs nodes; without it, brightness keybinds silently
    # fail to change /sys/class/backlight/*/brightness.
    udev.packages = [ pkgs.brightnessctl ];

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
      interfaces.tailscale0.allowedTCPPorts = [ 8080 ];
      interfaces.wlp1s0.allowedTCPPorts = [ 8080 ];
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
      monospace = [ "FiraCode Nerd Font Mono" ];
    };
  };

  boot.custom = {
    enable = true;
    type = "lanzaboote";
    efiSupport = true;
    # The pre-module ./boot.nix left systemd-boot's editor enabled; keep it
    # rather than silently taking the module's hardened default.
    editor = true;
  };

  boot = {
    binfmt.emulatedSystems = [ "aarch64-linux" ];
    kernelParams = [ "usbcore.autosuspend=-1" ];
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
      extraGroups = [
        "wheel"
        "audio"
        "video"
        "dialout"
        "uinput"
        "input"
        "lp"
      ]
      ++ lib.optional config.virtualisation.libvirtd.enable "libvirtd"
      ++ lib.optional config.networking.networkmanager.enable "networkmanager";
      initialPassword = "password";
      openssh.authorizedKeys.keys = [ ];
    };
  };

  system.stateVersion = "23.11";
}
