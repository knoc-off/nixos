{ pkgs, lib, config, ... }:
let
 mif = x: lib.mkIf config.services.yubikey-agent.enable x;
in
{


  services = {
    # Yubikey
    yubikey-agent.enable = lib.mkDefault true;
    pcscd.enable = true;
    udev.packages = mif [ pkgs.yubikey-personalization ];

  };
  programs = mif {
    gnupg.agent = {
      enable = lib.mkDefault true;
      enableSSHSupport = lib.mkDefault true;
    };
  };
}
