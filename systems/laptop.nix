# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running `nixos-help`).

{ lib, inputs, config, pkgs, ... }:

{
  imports =
    [
      # Include the results of the hardware scan.
      ./hardware/hardware-configuration.nix
      # move this to a flakes input
      #"${builtins.fetchTarball "https://github.com/nix-community/disko/archive/master.tar.gz"}/module.nix"
      #inputs.lanzaboote.nixosModules.lanzaboote
      #inputs.hardware

      ./hardware/disks/btrfs-luks.nix
    ];

  # Use the systemd-boot EFI boot loader.
  # disable if using lanzaboote
  boot.loader.systemd-boot.enable = true;

  boot.loader.efi.canTouchEfiVariables = true;


  # secureboot / lanzaboote
  #
  #  boot = {
  #    bootspec.enable = true;
  #    loader.systemd-boot.enable = lib.mkForce false;
  #    lanzaboote = {
  #      enable = true;
  #      pkiBundle = "/etc/secureboot";
  #    };
  #  };


  # enable setup mode
  # 1) Select the "Security" tab.
  # 2) Select the "Secure Boot" entry.
  # 3) Set "Secure Boot" to enabled.
  # 4) Select "Reset to Setup Mode".
  # 5) Select "Clear All Secure Boot Keys".
  # sudo nix run nixpkgs#sbctl enroll-keys -- --microsoft



  # networking.hostName = "nixos"; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  # networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  # time.timeZone = "Europe/Amsterdam";

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkbOptions in tty.
  # };

  # Enable the X11 windowing system.
  # services.xserver.enable = true;
  services.openssh = {
    enable = true;
    # require public key authentication for better security
    settings.PasswordAuthentication = false;
    settings.KbdInteractiveAuthentication = false;
    settings.PermitRootLogin = "yes";
  };


  # Configure keymap in X11
  services.xserver.layout = "us";
  # services.xserver.xkbOptions = "eurosign:e,caps:escape";

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;

  # Enable touchpad support (enabled default in most desktopManager).
  services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.knoff = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable ‘sudo’ for the user.
    initialPassword = "password";
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCzcqPB9VHe3vEaLRHEjtk39Y0cLIzl4MoInoMOIlHR3SmaNfaSYon64UGHydcTSoYusawKN+re+OPNHB/o04j7kW7Gfn3BDVzcwv2jADKmddC9fnhNz7YYC0S2aWMkvbXgzUmiQ3vC/g71xPYULKUBB0ZNKwV8DUjP/85Ft5I4CAfdcnss4410iVmWScLcmgZWHJgT0q0IAvdBQowMyJm5UIRINgZxOSOroEwgTFY74WNy/CKfx7/kDTte6OEgKwud99GhoA4o7up3GRXMPdFEut2af9iimIC7XyVRsTmQju1Jv1rf7KItRzAXGPYBNCz030Ak9bI1y8QwMYa1E/ZcnHXihdvAeEaJsUUPw9hmKOtNAtMnY42tRE4d+ihehZSKRhpXAUSoqdMvjCRNg2QjDvnv98GrAa7Mcbg7n5scCjuoczvaQ7cOAOGAYqLHLSBl9wqxUk9dZo0oTW/5NkHpslRNEy25biBqJukJAylLNXcB0YdnlTYDTcnyGtj9TIk= knoff" # content of authorized_keys file
    ];
    packages = with pkgs; [
      firefox
      tree
    ];
  };
  users.users.root.openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCzcqPB9VHe3vEaLRHEjtk39Y0cLIzl4MoInoMOIlHR3SmaNfaSYon64UGHydcTSoYusawKN+re+OPNHB/o04j7kW7Gfn3BDVzcwv2jADKmddC9fnhNz7YYC0S2aWMkvbXgzUmiQ3vC/g71xPYULKUBB0ZNKwV8DUjP/85Ft5I4CAfdcnss4410iVmWScLcmgZWHJgT0q0IAvdBQowMyJm5UIRINgZxOSOroEwgTFY74WNy/CKfx7/kDTte6OEgKwud99GhoA4o7up3GRXMPdFEut2af9iimIC7XyVRsTmQju1Jv1rf7KItRzAXGPYBNCz030Ak9bI1y8QwMYa1E/ZcnHXihdvAeEaJsUUPw9hmKOtNAtMnY42tRE4d+ihehZSKRhpXAUSoqdMvjCRNg2QjDvnv98GrAa7Mcbg7n5scCjuoczvaQ7cOAOGAYqLHLSBl9wqxUk9dZo0oTW/5NkHpslRNEy25biBqJukJAylLNXcB0YdnlTYDTcnyGtj9TIk= knoff" # content of authorized_keys file
  ];

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    wget
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 22 ];
  networking.firewall.allowedUDPPorts = [ 22 ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.05"; # Did you read the comment?

}





