{ lib, self, pkgs, ...}:
let
  inherit (lib) mkDefault mkBefore;
  inherit (self.packages.${pkgs.system}) grosshack;

  pam_fprintd_grosshackSo = "${grosshack}/lib/security/pam_fprintd_grosshack.so";

  grosshackConfig = ''
    auth  sufficient  ${pam_fprintd_grosshackSo} timeout=9999
    auth  sufficient  pam_unix.so try_first_pass nullok
  '';

  blinkScript = pkgs.writeScriptBin "blink" ''
    echo "$(date) - blink script executed" >> /var/log/blink_script.log
    echo 0 > /sys/class/leds/chromeos\:white\:power/brightness
    sleep 0.5
    echo 1 > /sys/class/leds/chromeos\:white\:power/brightness
  '';

  udevRule = ''
    ACTION=="add|change",
    SUBSYSTEM=="usb",
    ATTRS{idVendor}=="27c6",
    ATTRS{idProduct}=="609c",
    RUN+="${blinkScript}/bin/blink"
  '';

in
{
  services.fprintd = {
    enable = true;
  };

  services.udev.extraRules = udevRule;

  security.pam.services = {
    sudo.text = mkDefault (mkBefore grosshackConfig);
    login.text = mkDefault (mkBefore grosshackConfig);
    polkit-1.text = mkDefault (mkBefore grosshackConfig);
    ags.text = mkDefault (mkBefore grosshackConfig);
    swaylock.text = mkDefault (mkBefore grosshackConfig);
  };
}

