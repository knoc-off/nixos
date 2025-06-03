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

  # services.pipewire.wireplumber.configPackages = [
  #   (upkgs.writeTextDir "share/wireplumber/bluetooth.lua.d/99-codecs.lua" ''
  #     bluez_monitor.properties = {
  #       ["bluez5.codecs"] = { "sbc", "sbc_xq", "aac" }  # Prioritize basic codecs
  #     }
  #   '')
  # ];


  services.pipewire = {
    wireplumber = {
      configPackages = [
        (upkgs.writeTextDir "share/wireplumber/bluetooth.lua.d/99-a2dp-priority.lua" ''
          -- Custom WirePlumber Bluetooth Policy
          -- File: 99-a2dp-priority.lua
          -- Goal: Prioritize A2DP sink profile on device connection.

          -- Log a message to confirm this script is loaded (check with journalctl --user -u wireplumber -f)
          -- log.info("Loading custom Bluetooth A2DP priority policy")

          -- Access the properties table for the BlueZ monitor component
          bluez_monitor.properties = {

            -- *** The Key Setting: Auto-Connect Profile Order ***
            -- This table lists the Bluetooth profiles WirePlumber should attempt
            -- to automatically connect when a device appears. It tries them
            -- in the order listed. By putting "a2dp_sink" first, we prioritize it.
            ["bluez5.auto-connect"] = { "a2dp_sink", "hfp_hf" },
            -- "a2dp_sink": High-fidelity audio playback profile (what you want for music)
            -- "hfp_hf": Hands-Free Profile (for calls, includes mic + lower quality audio)
            -- You could also add "hsp_hs" (Headset Profile) if needed, but HFP is more common.


            -- == Include other desired Bluetooth settings below ==
            -- It's good practice to define all your desired settings here
            -- to ensure this policy takes precedence.

            -- Preferred Codec Order (highest quality first)
            ["bluez5.codecs"] = { "ldac", "aptx_hd", "aptx", "aac", "sbc_xq", "sbc" },

            -- Enable mSBC for better HFP call quality (if device supports it)
            ["bluez5.enable-msbc"] = true,

            -- Enable SBC XQ variant (slightly better than standard SBC)
            ["bluez5.enable-sbc-xq"] = true,

            -- Specify which headset roles to enable (HFP usually sufficient)
            ["bluez5.headset-roles"] = { "hfp_hf" },

            -- Optional: Control if WirePlumber automatically switches to HFP
            -- when an app requests the mic. Default is usually true.
            -- Setting to false might keep A2DP active but break auto-switching for calls.
            -- ["bluez5.autoswitch-profile"] = true,

            -- Optional: Allow hardware volume control for certain profiles
            -- ["bluez5.hw-volume"] = { "a2dp_sink", "hfp_hf" },
          }

          -- You could add more complex rules here if needed, e.g.,
          -- applying different settings based on device MAC address.
        '')
      ];
    };
  };



  boot.kernelParams = ["btusb.enable_autosuspend=0"];

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
      firmwareLinuxNonfree # Broadcom/Qualcomm adapters
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
