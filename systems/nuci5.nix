{ modulesPath, inputs, outputs, config, lib, pkgs, self, user, ... }: {
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

    # need some kind of WM
    # self.nixosModules.windowManager.hyprland
    {

      hardware.graphics.extraPackages = with pkgs; [
        intel-compute-runtime
        vaapiVdpau
        vaapiIntel
        intel-media-driver
      ];

      environment.variables.LIBVA_DRIVER_NAME = "i915";

      # doesnt need to be super secure here
      services = {
        getty.autologinUser = user;
        xserver.displayManager.startx.enable = false;
        greetd.enable = false;
      };

      # Ensure the user exists (replace with your actual user settings)
      users.users.${user} = {
        isNormalUser = true;
        extraGroups = [ "wheel" "render" "seat" "video" "audio" "input" "networkmanager" ]; # Add necessary groups
        # shell = pkgs.bash; # Or your preferred shell
        # home = "/home/${autoLoginUser}"; # Optional: Explicitly set home if needed
        # uid = 1000; # Optional: Set UID if needed

        # --- Systemd User Service for Hyprland ---
        # This service will be automatically started when 'autoLoginUser' logs in.
      };
      # Make sure these groups exist
      users.groups = {
        input = {};
        render = {};
        seat = {};
      };
      services.xserver.displayManager.sessionPackages = [ pkgs.dwl ];

      systemd.user.services.my-service = {
        description = "My custom service";
        wantedBy = [ "default.target" ];
        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.dwl}/bin/dwl";
          Restart = "on-failure";
        };
      };



      # System-wide packages
      environment.systemPackages = lib.mkDefault (with pkgs; [
        wl-clipboard
        xdg-utils

        dwl
        firefox

      ]);

    }

    inputs.hardware.nixosModules.common-cpu-intel

    # nix package settings
    ./modules/nix.nix

    # VPN Server
    # ./services/wireguard.nix

    # Syncthing
    # ./services/syncthing.nix # this should be enabled again, for media?

  ];
  nix.settings.auto-optimise-store = true;

  networking.hostName = "nux";
  # Firewall
  networking.firewall = {
    enable = true;
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
