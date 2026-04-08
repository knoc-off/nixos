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
    # inputs.nixgl.packages.x86_64-linux.nixGLIntel

    inputs.determinate.nixosModules.default

    self.nixosModules.services.dagu
    {
      services.dagu = {
        enable = true;
        port = 9090;
        settings = {
          auth.mode = "none";
          terminal.enabled = true;
          ui.navbar_title = "Dagu";
        };
      };
    }

    self.nixosModules.home
    self.nixosModules.nix
    self.nixosModules.audio.pipewire

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
    self.nixosModules.desktop.noctalia

    inputs.hardware.nixosModules.framework-13-7040-amd
    {
      hardware.uinput.enable = true;
    }

    {
      # services.ivpn.enable = true;
      services.mullvad-vpn.enable = true;
    }

    self.nixosModules.services.lspmux
    {services.lspmux.enable = true;}

    self.nixosModules.services.logiops
    {
      services.logiops = {
        enable = true;
        config = ''
          io_timeout: 60000.0;

          devices: (
          {
              name: "MX Master 3S";
              smartshift: // when scrolling fast it goes to different mode.
              {
                  on: false;
                  threshold: 30;
                  torque: 50;
              };
              dpi: 1000;
              scroll:
              {
                  hires: true;
                  invert: false;
                  target: false;
              };
              thumbwheel:
              {
                  divert: false;
                  invert: false;
                  proxy:
                  {
                      type: "Keypress";
                      keys: ["KEY_F21"];
                  };
                  touch:
                  {
                      type: "Keypress";
                      keys: ["KEY_F22"];
                  };
                  tap:
                  {
                      type: "Keypress";
                      keys: ["KEY_F23"];
                  };
              };
              buttons: (
                  {
                      cid: 0x52;
                      action:
                      {
                          type: "Keypress";
                          keys: ["KEY_F13"];
                      };
                  },
                  {
                      cid: 0x53;
                      action:
                      {
                          type: "Keypress";
                          keys: ["KEY_F14"];
                      };
                  },
                  {
                      cid: 0x56;
                      action:
                      {
                          type: "Keypress";
                          keys: ["KEY_F15"];
                      };
                  },
                  {
                      cid: 0xc3;
                      action:
                      {
                          type: "Keypress";
                          keys: ["KEY_F16"];
                      };
                  },
                  {
                      cid: 0xc4;
                      action:
                      {
                          type: "Keypress";
                          keys: ["KEY_F17"];
                      };
                  },
                  {
                      cid: 0xd7;
                      action:
                      {
                          type: "Keypress";
                          keys: ["KEY_F18"];
                      };
                  }
              );
          }
          );

        '';
      };
    }

    ./hardware/boot.nix

    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/${hostname}/default.yaml;
        age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
        secrets."shell_environment/OPENROUTER_API_KEY" = {
          mode = "0644";
        };
        secrets."shell_environment/ANTHROPIC_API_KEY" = {
          mode = "0644";
        };
        secrets."wireguard/private-key" = {};
      };
    }

    ./services/wireguard.nix

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

    wireguard.interfaces.wg0 = {
      ips = ["10.100.0.4/24"];
      privateKeyFile = config.sops.secrets."wireguard/private-key".path;

      # Tell systemd-resolved to route *.niko.ink queries to the hub's
      # dnsmasq over the tunnel. All other DNS goes through the normal
      # resolver. This is the systemd-resolved equivalent of split DNS.
      postSetup = ''
        ${pkgs.systemd}/bin/resolvectl dns wg0 10.100.0.1
        ${pkgs.systemd}/bin/resolvectl domain wg0 "~niko.ink"
      '';
      postShutdown = ''
        ${pkgs.systemd}/bin/resolvectl revert wg0
      '';

      peers = [
        {
          publicKey = "xhsyVKOlzOHtOSDsXU7d/CRdyzamNgotO8NocNLpFno=";
          endpoint = "157.90.17.55:51820";
          allowedIPs = ["10.100.0.0/24"];
          persistentKeepalive = 25;
        }
      ];
    };

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
