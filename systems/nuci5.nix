{ modulesPath, inputs, hostname, outputs, config, lib, pkgs, self, user, ...
}@args: {
  imports = [
    # Sops
    # inputs.sops-nix.nixosModules.sops
    # {
    #   sops = {
    #     defaultSopsFile = ./secrets/hetzner/default.yaml;
    #     # This will automatically import SSH keys as age keys
    #     age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    #     secrets = if config.services.nextcloud.enable then {
    #       "services/nextcloud/admin-pass" = {
    #         owner = config.users.users.nextcloud.name;
    #       };
    #     } else
    #       { };
    #   };
    # }

    # Disko
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix

    (self.nixosModules.home { inherit args; })

    # need some kind of WM
    # self.nixosModules.windowManager.hyprland
    {

      hardware.graphics.extraPackages = with pkgs; [
        intel-compute-runtime
        vaapiVdpau
        vaapiIntel
        intel-media-driver
      ];

      # XDG portal configuration
      xdg.portal = {
        enable = lib.mkDefault true;
        extraPortals = lib.mkDefault [
          pkgs.xdg-desktop-portal-gtk
          pkgs.xdg-desktop-portal-hyprland
        ];
      };
      xdg.portal.config.common.default = "*";

      environment.variables.LIBVA_DRIVER_NAME = "i915";

      # might want to swap over to cage. but dwl is more powerful, if i want to run web-browser
      # services.cage.user = "kodi";
      # services.cage.program = "${pkgs.kodi-wayland}/bin/kodi-standalone";
      # services.cage.enable = true;

      # doesnt need to be super secure here
      services = {
        xserver.displayManager.startx.enable = false;
        greetd = {
          enable = true;
          settings = {
            default_session = {
              #command = "${pkgs.dwl}/bin/dwl -s kodi";
              command = "${pkgs.dwl}/bin/dwl -s firefox";
              #command = "${pkgs.bash}/bin/bash";
              inherit user;
            };
          };
        };
        seatd = {
          enable = true;
          inherit user;
        };
      };

      # Ensure the user exists (replace with your actual user settings)
      users.users.${user} = {
        isNormalUser = true;
        extraGroups =
          [ "wheel" "render" "seat" "video" "audio" "input" "networkmanager" ];

        # packages = with pkgs; [ dwl ];
      };
      # Make sure these groups exist
      users.groups = {
        input = { };
        render = { };
        seat = { };
      };
      #services.displayManager.sessionPackages = [pkgs.dwl];

      # System-wide packages
      environment.systemPackages = lib.mkDefault (with pkgs; [
        wl-clipboard
        xdg-utils

        dwl
        firefox

        bluetuith # TUI manager
        bluez-tools # CLI utilities
        bluez-alsa # ALSA backend (optional)
        wireshark # HCI analysis
      ]);

      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        package = pkgs.bluez.override { enableExperimental = true; };
        settings = {
          General = {
            ControllerMode = "dual"; # BR/EDR + LE
            JustWorksRepairing = "always"; # Fix pairing issues
            Experimental = true; # Battery reports
            FastConnectable = true;
            ReconnectAttempts = 7;
          };
        };
        disabledPlugins = [ "sap" ]; # Disable SIM Access Profile
      };
      services.blueman.enable = true; # GUI manager

    }

    # {
    #   # create a service to run at startup each boot. run wgnord c de to connect to the vpn
    #   systemd.services.wgnord = {
    #     description = "WireGuard NordVPN";
    #     after = [ "network.target" ];
    #     wantedBy = [ "multi-user.target" ];
    #     serviceConfig = {
    #       Type = "oneshot";
    #       ExecStart = "${pkgs.wgnord}/bin/wgnord c de";
    #     };
    #   };
    # }

    #inputs.hardware.nixosModules.common-cpu-intel

    # nix package settings
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

    # VPN Server
    # ./services/wireguard.nix

    # Syncthing
    # ./services/syncthing.nix # this should be enabled again, for media?

  ];

  nix.settings.auto-optimise-store = true;

  networking.hostName = hostname;

  # Firewall
  networking.firewall = {
    enable = false;
    allowedTCPPorts = [ ];
  };

  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;

  environment.systemPackages = map lib.lowPrio [ pkgs.curl pkgs.gitMinimal ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "24.11";
}
