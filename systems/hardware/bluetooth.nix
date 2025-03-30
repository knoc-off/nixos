{ config, upkgs, lib, ... }:

{
  # ======================
  # Bluetooth Core
  # ======================
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    package = upkgs.bluez.override { enableExperimental = true; };
    settings = {
      General = {
        ControllerMode = "dual";       # BR/EDR + LE
        JustWorksRepairing = "always"; # Fix pairing issues
        Experimental = true;           # Battery reports
        FastConnectable = true;
        ReconnectAttempts = 7;
      };
    };
    disabledPlugins = ["sap"];         # Disable SIM Access Profile
  };

  services.blueman.enable = true;      # GUI manager

  # ======================
  # Kernel & Low-Level
  # ======================
  boot.kernelModules = ["btusb" "btbcm" "btintel"];
  boot.extraModprobeConfig = ''
    options btusb enable_iso_sockets=1  # Required for LE Audio
    options btusb enable_autosuspend=0  # Prevent random disconnects
  '';

  # ======================
  # Device Management
  # ======================
  services.udev.extraRules = ''
    # Power management
    ACTION=="add", SUBSYSTEM=="bluetooth", ATTR{power/control}="on"

    # CSR8510 dongle fix
    ATTR{idVendor}=="0a12", ATTR{idProduct}=="0001", RUN+="${upkgs.bluez}/bin/hciconfig hci0 up"
  '';

  hardware.firmware = with upkgs; [
    firmwareLinuxNonfree  # Broadcom/Qualcomm adapters
  ];

  # ======================
  # Bluetooth Tools
  # ======================
  environment.systemPackages = with upkgs; [
    bluetuith       # TUI manager
    bluez-tools     # CLI utilities
    bluez-alsa      # ALSA backend (optional)
    wireshark       # HCI analysis
  ];

  # ======================
  # MPRIS Proxy (Media Controls)
  # ======================
  systemd.user.services.mpris-proxy = {
    description = "Bluetooth MPRIS proxy";
    after = ["bluetooth.target"];
    wants = ["bluetooth.target"];
    serviceConfig = {
      ExecStart = "${upkgs.bluez}/bin/mpris-proxy";
      Restart = "on-failure";
    };
    wantedBy = ["default.target"];
  };
}

