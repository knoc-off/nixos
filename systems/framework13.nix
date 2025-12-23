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

    # make this a hardware module?
    ./hardware/disks/btrfs-luks.nix

    # Hardware configs
    ./hardware/hardware-configuration.nix
    ./hardware/bluetooth.nix
    ./hardware/fingerprint
    #./services/rclone-client.nix
    {
      sops.secrets."services/rclone/webdav-pass" = {
        mode = "0444"; # World-readable so home-manager can access it
        path = "/etc/rclone-webdav-pass";
      };
    }

    inputs.hardware.nixosModules.framework-13-7040-amd

    # Enable uinput for kanata and logiops for mouse
    {
      hardware.uinput.enable = true;
    }

    {
      # ivpn
      services.ivpn.enable = true;
    }

    # {
    #   systemd.services.esphome.serviceConfig = {
    #     MemoryDenyWriteExecute = lib.mkForce false;
    #   };
    #   # esp32
    #   nixpkgs.config.permittedInsecurePackages = [
    #     "python3.12-ecdsa-0.19.1"
    #   ];

    #   services.esphome = {
    #     enable = true;
    #     openFirewall = true; # if you want to access dashboard from other devices
    #     allowedDevices = [
    #       "char-ttyUSB" # for flashing via USB
    #       "char-ttyACM" # ESP32-C3 often shows up as ACM
    #     ];
    #   };
    # }

    # Logiops for MX Master 3S mouse configuration
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

    # module to setup boot
    ./hardware/boot.nix

    # Sops. I think this could be some kind of module. to abstract the setup.
    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        defaultSopsFile = ./secrets/${hostname}/default.yaml;
        # This will automatically import SSH keys as age keys
        age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
        secrets."ANTHROPIC_API_KEY" = {
          mode = "0644";
        };
      };
    }

    # Nix package settings
    {
      nixpkgs.config.allowUnfree = true; # TODO swap out for my nix-module.
      nix = {
        registry = {
          nixpkgs.flake = inputs.nixpkgs;
          nixos-hardware.flake = inputs.hardware;
        };
        #nix.nixPath = [ "/etc/nix/path" ];
        #environment.etc."nix/path/nixpkgs".source = inputs.nixpkgs;
        nixPath = ["nixpkgs=${inputs.nixpkgs}"];
      };
    }

    # Window manager
    self.nixosModules.windowManager.hyprland
    {
      services.greetd = let
        tuigreet = "${pkgs.tuigreet}/bin/tuigreet";
        hyprland = "${pkgs.hyprland}/bin/Hyprland";
      in {
        enable = true;
        settings = {
          default_session.command = "${tuigreet} --remember --cmd ${hyprland}";

          # default_session.command =
          #   "./${pkgs.greetd.tuigreet}/bin/tuigreet --remember --cmd ./${
          #     pkgs.writeScriptBin "Hyprland_start" ''
          #       ${pkgs.hyprland}/bin/Hyprland
          #     ''
          #   }";
          # default_session = {
          #   command = "./${hyprland}";
          #   user = "knoff";
          # };
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

  security.sudo.extraRules = [
    {
      #groups = [ "networkmanager" ];
      users = [user];
      #groups = [ 1006 ];
      commands = [
        {
          command = "${pkgs.wgnord}/bin/wgnord"; # is this a security issue? its not writable
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  programs = {
    # not super needed.
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

      # Allow users in input group to access input devices for kanata
      KERNEL=="event[0-9]*", GROUP="input", MODE="0660"
      KERNEL=="uinput", GROUP="uinput", MODE="0660"
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
      #pkgs.nerd-fonts.droid-sans-mono
    ];
    fontconfig.defaultFonts = {
      monospace = ["FiraCode Nerd Font Mono"];
    };
  };

  # Set default values for the new options
  bootloader = {
    type = "lanzaboote";
    efiSupport = true;
  };

  boot = {
    #kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

    # fingerpritn scanner does not work without this, suddenly. TODO: Try to remove this
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
          # we should automate this. if networkmanager is enabled, then add it, etc.
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
