{
  pkgs,
  lib,
  ...
}: {
  networking.networkmanager.enable = lib.mkDefault true;

  console.keyMap = lib.mkDefault "us";

  programs = {dconf.enable = lib.mkDefault true;};

  services = {
    resolved.enable = lib.mkDefault true;
    fwupd.enable = lib.mkDefault true;
    openssh = {
      enable = lib.mkDefault true;
      settings.PermitRootLogin = lib.mkDefault "no";
    };
    xserver.xkb.layout = lib.mkDefault "us";
    printing.enable = lib.mkDefault true;
    avahi = {
      enable = lib.mkDefault true;
      nssmdns4 = lib.mkDefault true;
    };
    libinput.enable = lib.mkDefault true;
  };

  fonts = {enableDefaultPackages = lib.mkDefault true;};

  environment.systemPackages = lib.mkDefault (with pkgs; [
    git
    wget
    libinput
  ]);

  time.timeZone = lib.mkDefault "Europe/Berlin";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
}
