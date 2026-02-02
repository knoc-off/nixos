{ config, upkgs, lib, ... }: {
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    package = upkgs.bluez.override { enableExperimental = true; };
    settings = {
      General = {
        ControllerMode = "dual";
        JustWorksRepairing = "always";
        Experimental = true;
        FastConnectable = true;
      };
    };
    disabledPlugins = [ "sap" ];
  };

  services.blueman.enable = true;

  boot.extraModprobeConfig = ''
    options btusb enable_iso_sockets=1
    options btusb enable_autosuspend=0
  '';
  boot.kernelModules = [ "btusb" "btbcm" "btintel" "bluetooth" ];

  boot.kernelParams = [ "btusb.enable_autosuspend=0" ];

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="bluetooth", ATTR{power/control}="on"

    ATTR{idVendor}=="0a12", ATTR{idProduct}=="0001", RUN+="${upkgs.bluez}/bin/hciconfig hci0 up"
  '';

  hardware.firmware = with upkgs;
    [
      linux-firmware
    ];

  environment.systemPackages = with upkgs; [
    bluetuith
    bluez-tools
    bluez-alsa
    wireshark
  ];

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
