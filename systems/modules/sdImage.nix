{
  config,
  pkgs,
  lib,
  modulesPath,
  system,
  ...
} @ options: let
in {
  imports = ["${modulesPath}/installer/sd-card/sd-image-aarch64.nix"];
  config =
    {
      # ZFS is enabled by default in installer profiles but is never cached
      # (built against specific kernel versions). Disable it for SD images.
      boot.supportedFilesystems.zfs = lib.mkForce false;

      # The all-hardware profile includes dw-hdmi which was renamed/removed
      # in newer kernels and doesn't exist in the RPi kernel. Disable it.
      hardware.enableAllHardware = lib.mkForce false;
      users.users.root.openssh.authorizedKeys.keys = lib.mkForce [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink"
      ];

      # Enable SSH for remote access
      services.openssh.enable = lib.mkForce true;
      services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

      # Add any additional packages you want in the live environment
      environment.systemPackages = with pkgs; [
        vim
        git
        wget
        htop
      ];

      # Optional: Set your preferred time zone
      time.timeZone = "Europe/Berlin";

      networking.networkmanager.enable = lib.mkForce false;
    }
    //
    # Check if disko option exists before forcing it false
    (
      if lib.hasAttr "disko" options
      then {
        disko.enableConfig = lib.mkForce false;
      }
      else {}
    );
}
