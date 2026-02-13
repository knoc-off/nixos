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
    self.nixosModules.home
    self.nixosModules.nix
    self.nixosModules.audio.pipewire

    self.nixosModules.misc
    self.nixosModules.minecraft.server-suite

    inputs.disko.nixosModules.disko
    {disko.devices.disk.vdb.device = "/dev/nvme0n1";}

    ./hardware/disks/btrfs-luks.nix

    ./hardware/hardware-configuration.nix
    ./hardware/bluetooth.nix
    ./hardware/fingerprint
    {
      sops.secrets."services/rclone/webdav-pass" = {
        mode = "0444"; # World-readable so home-manager can access it
        path = "/etc/rclone-webdav-pass";
      };
    }

    # niri configs
    inputs.niri.nixosModules.niri
    {
      nixpkgs.overlays = [inputs.niri.overlays.niri];
      programs.niri = {
        enable = true;
        package = pkgs.niri-unstable;
      };
    }

    self.nixosModules.desktop.noctalia

    inputs.hardware.nixosModules.framework-13-7040-amd
    {
      hardware.uinput.enable = true;
    }

    {
      # services.ivpn.enable = true;
      services.mullvad-vpn.enable = true;
    }

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
        secrets."ANTHROPIC_API_KEY" = {
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
        niri-session = "${pkgs.niri-unstable}/bin/niri-session";
      in {
        enable = true;
        settings = {
          default_session = {
            command = "${tuigreet} --time --remember --cmd ${niri-session}";
            user = "greeter";
          };
        };
      };
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
  services = {
    gvfs.enable = true;
    devmon.enable = true;
    udisks2.enable = true;
    upower.enable = true;
    accounts-daemon.enable = true;

    logind = {
      lidSwitch = "suspend";
      powerKey = "suspend";
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

  system.activationScripts = {
    createMountPoint = {
      text = ''
        mkdir -p /mnt/fa6b949
      '';
    };
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
    kernelParams = ["usbcore.autosuspend=-1"];
    kernel.sysctl = {
      "vm.swappiness" = 20;
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
