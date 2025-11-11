{ config, upkgs, lib, ... }: {
  # ======================
  # Bluetooth Core
  # ======================
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    package = upkgs.bluez.override { enableExperimental = true; };
    settings = {
      General = {
        ControllerMode = "dual"; # BR/EDR + LE
        JustWorksRepairing = "always"; # Fix pairing issues
        Experimental = true; # Battery reports
        FastConnectable = true;
      };
    };
    disabledPlugins = [ "sap" ]; # Disable SIM Access Profile
  };

  services.blueman.enable = true; # GUI manager

  # ======================
  # Kernel & Low-Level
  # ======================
  boot.extraModprobeConfig = ''
    options btusb enable_iso_sockets=1
    options btusb enable_autosuspend=0
  '';
  boot.kernelModules = [ "btusb" "btbcm" "btintel" "bluetooth" ];

  boot.kernelParams = [ "btusb.enable_autosuspend=0" ];

  # services.pipewire.wireplumber.configPackages = [
  #   (upkgs.writeTextDir "share/wireplumber/bluetooth.lua.d/99-codecs.lua" ''
  #     bluez_monitor.properties = {
  #       ["bluez5.codecs"] = { "sbc", "sbc_xq", "aac" }  # Prioritize basic codecs
  #     }
  #   '')
  # ];

  # services.pipewire = {
  #   wireplumber = {
  #     configPackages = [
  #       (upkgs.writeTextDir
  #         "share/wireplumber/bluetooth.lua.d/99-airpods-fix.lua" ''
  #           -- Minimalist config for testing AirPod stability
  #           bluez_monitor.properties = { alegreya-sans
  #             -- Prioritize high-quality audio sink on connection
  #             ["bluez5.auto-connect"] = { "a2dp_sink", "hfp_hf" },

  #             -- Prioritize the codec AirPods actually use
  #             ["bluez5.codecs"] = { "aac", "sbc" },

  #             -- Enable mSBC for better call quality if the HFP profile is used
  #             ["bluez5.enable-msbc"] = true,
  #           }
  #         '')
  #     ];
  #   };
  # };


  # ======================
  # Device Management
  # ======================
  services.udev.extraRules = ''
    # Power management
    ACTION=="add", SUBSYSTEM=="bluetooth", ATTR{power/control}="on"

    # CSR8510 dongle fix
    ATTR{idVendor}=="0a12", ATTR{idProduct}=="0001", RUN+="${upkgs.bluez}/bin/hciconfig hci0 up"
  '';

  hardware.firmware = with upkgs;
    [
      linux-firmware # Broadcom/Qualcomm adapters
    ];

  # ======================
  # Bluetooth Tools
  # ======================
  environment.systemPackages = with upkgs; [
    bluetuith # TUI manager
    bluez-tools # CLI utilities
    bluez-alsa # ALSA backend (optional)
    wireshark # HCI analysis
  ];

  # ======================
  # MPRIS Proxy (Media Controls)
  # ======================
  systemd.user.services.mpris-proxy = {
    description = "Bluetooth MPRIS proxy";
    after = [ "bluetooth.target" ];
    wants = [ "bluetooth.target" ];
    serviceConfig = {
      ExecStart = "${upkgs.bluez}/bin/mpris-proxy";
      Restart = "on-failure";
    };
    wantedBy = [ "default.target" ];
  };
}
