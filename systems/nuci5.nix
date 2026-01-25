{
  inputs,
  hostname,
  lib,
  pkgs,
  self,
  user,
  config,
  ...
} @ args: {
  imports = [
    # Disko
    inputs.disko.nixosModules.disko
    ./hardware/disks/simple-disk.nix
    ./services/kdeconnect.nix
    ./services/home-assistant.nix

    self.nixosModules.audio.pipewire
    self.nixosModules.home
    self.nixosModules.nix

    # need some kind of WM
    self.nixosModules.windowManager.hyprland
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
        # Only the essential packages
        extraPackages = with pkgs; [
          mesa
          intel-media-driver
          intel-vaapi-driver
          libdrm
        ];
      };

      # doesnt need to be super secure here
      services = {
        xserver.displayManager.startx.enable = false;
        getty.autologinUser = user;
        greetd = {
          enable = true;
          settings = {
            default_session = {
              command = "${pkgs.hyprland}/bin/Hyprland";
              inherit user;
            };
          };
        };
        seatd = {
          enable = true;
          inherit user;
        };
      };

      users.users.${user} = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "render"
          "seat"
          "video"
          "audio"
          "input"
          "networkmanager"
          "dialout"
          "plugdev"
        ];
      };

      # System-wide packages
      environment.systemPackages = with pkgs; [
        # DRM/Graphics debugging tools
        libdrm
        mesa-demos # Contains glxinfo for debugging
        vulkan-tools

        # Your existing packages
        wl-clipboard
        xdg-utils
        dwl
        firefox
        mpv

        # Bluetooth
        bluetuith
        bluez-tools
        bluez-alsa
        wireshark

        # HDMI-CEC for controlling TV
        libcec # Provides cec-client for sending CEC commands
      ];

      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
        package = pkgs.bluez.override {enableExperimental = true;};
        settings = {
          General = {
            ControllerMode = "dual"; # BR/EDR + LE
            JustWorksRepairing = "always"; # Fix pairing issues
            Experimental = true; # Battery reports
            FastConnectable = true;
            ReconnectAttempts = 7;
          };
        };
        disabledPlugins = ["sap"]; # Disable SIM Access Profile
      };
      services.blueman.enable = true; # GUI manager
    }

    {
      # Hardware support for Steam devices
      hardware.steam-hardware.enable = true;

      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      # Sound support (choose one)
      services.pipewire.alsa.support32Bit = true; # For PipeWire
    }
  ];

  services.dbus.enable = true;

  # Enable uinput for KDE Connect remote input (mouse/keyboard from phone)
  hardware.uinput.enable = true;

  nix.settings.auto-optimise-store = true;

  networking.hostName = hostname;

  # Firewall
  networking.firewall = {
    enable = false; # Ensure firewall is active
    allowedTCPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
    allowedUDPPortRanges = [
      {
        from = 1714;
        to = 1764;
      }
    ];
  };

  boot = {
    kernelModules = [
      "i915"
      "cec" # HDMI-CEC support
      "drm" # DRM subsystem for CEC
    ];
    kernelParams = [
      # Ensure Intel graphics are properly initialized
      "i915.modeset=1"
      "i915.preliminary_hw_support=1"
    ];
  };
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  services.openssh.enable = true;

  time.timeZone = "Europe/Berlin";

  environment.systemPackages = [
    pkgs.curl
    pkgs.gitMinimal

    inputs.nixgl.packages.x86_64-linux.nixGLIntel
  ];

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
  ];

  system.stateVersion = "24.11";
}
