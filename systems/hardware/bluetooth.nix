{ pkgs, ... }:
{
  hardware.bluetooth.enable = true; # enables support for Bluetooth
  hardware.bluetooth.powerOnBoot = true; # powers up the default Bluetooth controller on boot

  services.blueman.enable = true;

  hardware.bluetooth.settings = {
    General = {
      # A2dpSink support
      Enable = "Source,Sink,Media,Socket";
      # device battery level
      Experimental = true;
    };
  };

  # for buttons on devices
  #systemd.user.services.mpris-proxy = {
  #    description = "Mpris proxy";
  #    after = [ "network.target" "sound.target" ];
  #    wantedBy = [ "default.target" ];
  #    serviceConfig.ExecStart = "${pkgs.bluez}/bin/mpris-proxy";
  #};

  # additional codecs
  #  hardware.pulseaudio = {
  #    enable = true;
  #    package = pkgs.pulseaudioFull;
  #  };


}
