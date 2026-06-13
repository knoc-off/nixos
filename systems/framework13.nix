{
  lib,
  inputs,
  pkgs,
  self,
  config,
  ...
}: let
  user = "knoff";
in {
  imports = [
    # inputs.nixgl.packages.x86_64-linux.nixGLIntel

    inputs.determinate.nixosModules.default

    self.nixosModules.users.knoff
    self.nixosModules.nix
    self.nixosModules.nh
    self.nixosModules.pipewire

    self.nixosModules.misc
    self.nixosModules.console
    self.nixosModules.minecraft

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
        defaultSopsFile = ./secrets/framework13/default.yaml;
        age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
        secrets."shell_environment/OPENROUTER_API_KEY" = {
          mode = "0644";
        };
        # secrets."shell_environment/ANTHROPIC_API_KEY" = {
        #   mode = "0644";
        # };
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

  security.sudo.extraRules = [
    {
      users = [user];
      commands = [
        {
          command = "${pkgs.wgnord}/bin/wgnord";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

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

  # Tailnet client. Enroll once interactively:
  #   sudo tailscale up --login-server https://headscale.niko.ink
  # MagicDNS (accept-dns defaults on) resolves the niko.ink service names
  # to their tailnet IPs, replacing the old wg0 resolvectl split DNS.
  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  networking = {
    hostName = "framework13";

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
      "vm.swappiness" = 20;
      # Increase inotify limits for rust-analyzer and other file watchers
      "fs.inotify.max_user_watches" = 524288;
      "fs.inotify.max_user_instances" = 1024;
    };
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
