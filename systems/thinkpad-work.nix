{
  lib,
  inputs,
  pkgs,
  self,
  hostname,
  user,
  config,
  ...
}: {
  imports = [
    inputs.determinate.nixosModules.default
    {
      # WORKAROUND: kernel 6.19+ btrfs causes the overlayfs stale-file-handle
      # functional test to fail deterministically.  Disable the check phase so
      # determinate-nix builds without running nix-functional-tests.
      # Remove once upstream fixes the test or a newer determinate release lands.
      nix.package = lib.mkForce (
        inputs.determinate.inputs.nix.packages.${pkgs.stdenv.system}.default.overrideAttrs (_: {
          doCheck = false;
        })
      );
    }

    self.nixosModules.home
    self.nixosModules.nix
    self.nixosModules.audio.pipewire

    self.nixosModules.misc
    self.nixosModules.console

    self.nixosModules.disks."btrfs-luks"

    ./hardware/hardware-configuration-thinkpad-work.nix
    ./hardware/bluetooth.nix
    ./hardware/fingerprint

    self.nixosModules.hyprland
    self.nixosModules.desktop.noctalia

    self.nixosModules.windows-vm
    {
      windows-vm = {
        enable = true;
        mergeAutounattendFile = "${inputs.UnattendedWinstall}/autounattend.xml";
      };
    }

    inputs.hardware.nixosModules.lenovo-thinkpad
    inputs.hardware.nixosModules.common-cpu-intel
    inputs.hardware.nixosModules.common-gpu-intel
    inputs.hardware.nixosModules.common-pc-laptop
    inputs.hardware.nixosModules.common-pc-ssd

    {
      # Arrow Lake-P (PCI ID 7d51) GPU driver selection:
      # xe: i915_flip kworkers get stuck in D-state, causing system-wide I/O
      #     stalls and intermittent multi-second freezes (kernel 6.19.3).
      # i915: has had GPU HANG reports on this hardware in earlier kernels.
      # Using i915 for now as the lesser of two evils — revisit when xe
      # display flip handling matures.
      hardware.intelgpu.driver = "i915";
      boot.blacklistedKernelModules = [
        "ac" # battery issues with detection
      ];
      hardware.uinput.enable = true;
    }

    self.nixosModules.services.lspmux
    {services.lspmux.enable = true;}

    self.nixosModules.boot

    # TODO: re-enable after first install when SSH host keys exist for sops/age
    # inputs.sops-nix.nixosModules.sops
    # {
    #   sops = {
    #     defaultSopsFile = ./secrets/${hostname}/default.yaml;
    #     age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    #     secrets."ANTHROPIC_API_KEY" = {
    #       mode = "0644";
    #     };
    #   };
    # }

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

    ./modules/shell/fish.nix

    #./modules/yubikey.nix
  ];

  services.power-profiles-daemon.enable = true;

  disks.btrfsLuks = {
    enable = true;
    device = "/dev/nvme0n1";
    swapSize = "32G";
    hibernation = true;
  };

  programs = {
    direnv = {
      enable = true;
      silent = true;
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
        stdenv.cc.cc
        SDL2
        SDL2_image
        libz
      ];
    };
    dconf.enable = true;
  };

  programs.steam.enable = true;

  # Suspend-then-hibernate: suspend to RAM first, auto-hibernate after 30 min
  systemd.sleep.extraConfig = ''
    HibernateDelaySec=30min
  '';
  services = {
    gvfs.enable = true;
    devmon.enable = true;
    udisks2.enable = true;
    upower.enable = true;
    accounts-daemon.enable = true;

    logind = {
      lidSwitch = "suspend-then-hibernate";
      powerKey = "hibernate"; # lock instead TODO
      powerKeyLongPress = "poweroff";
    };

    # flatpak.enable = true;

    resolved.enable = true;

    fwupd.enable = true;

    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    xserver.xkb.layout = "us";

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
    hostName = hostname;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22000
        38071
        21027
        53317
      ];
      allowedUDPPorts = [
        54321
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

  systemd.tmpfiles.rules = ["d /var/secrets 0750 root root -"];

  networking.wg-quick.interfaces.wg0 = {
    configFile = "/var/secrets/wg0-tunnel-work.conf";
  };

  boot.custom = {
    enable = true;
    # After first install: enroll secure boot keys with `sbctl`, then switch to "lanzaboote"
    # type = "lanzaboote";
    type = "systemd-boot";
    efiSupport = true;
  };

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
      "usbcore.autosuspend=-1"
      "resume=/dev/mapper/crypted"
      # Physical offset of /.swapvol/swapfile within the btrfs filesystem.
      # Obtain with: sudo btrfs inspect-internal map-swapfile -r /.swapvol/swapfile
      # Must be updated if the swapfile is ever recreated (e.g. swapSize changes).
      "resume_offset=533760"
      # Let i915 claim the Arrow Lake-P GPU normally no force_probe
    ];
    kernel.sysctl = {
      # Minimize swap usage — plenty of RAM available; only swap under real
      # memory pressure.  Keeps the slow btrfs swap file for hibernation only.
      "vm.swappiness" = 1;
      # Reclaim vfs caches less aggressively (default 100 = equal pressure on
      # page-cache vs dentries/inodes; 50 = keep more dentries/inodes cached)
      "vm.vfs_cache_pressure" = 50;
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
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID7HocV04erAJfAT9swZ/PBsrVkwySxkX5b6rGRaTXAh niko@mac"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
      ];
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID7HocV04erAJfAT9swZ/PBsrVkwySxkX5b6rGRaTXAh niko@mac"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  virtualisation = {
    containers.enable = true;
    podman = {
      enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  environment.systemPackages = with pkgs; [
    awscli2
    podman-compose
    postgresql
  ];

  system.stateVersion = "23.11";
}
