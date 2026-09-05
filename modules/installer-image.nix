# Shared config for the throwaway installer/live images built by
# flake.nix's mkImage (isoImage, sdImage). Not a host: no identity, no
# secrets, just "be a usable live environment I can SSH into."
{ self, ... }:
{
  nixos =
    {
      lib,
      pkgs,
      options,
      ...
    }:
    {
      config =
        {
          users.users.root.openssh.authorizedKeys.keys = lib.mkForce [ self.lib.ssh.user.framework13 ];
          services.openssh.enable = lib.mkForce true;
          services.openssh.settings.PermitRootLogin = lib.mkForce "yes";

          environment.systemPackages = with pkgs; [
            vim
            git
            wget
            htop
          ];

          time.timeZone = "Europe/Berlin";
          networking.networkmanager.enable = lib.mkForce false;
        }
        // (
          # Check if disko option exists before forcing it false
          if lib.hasAttr "disko" options then
            {
              disko.enableConfig = lib.mkForce false;
            }
          else
            { }
        );
    };
}
