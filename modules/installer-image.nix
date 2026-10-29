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

          # Reachable as <hostname>.local without reading an IP off the
          # console. On a name clash avahi renames itself (<hostname>-2.local)
          # and logs it.
          services.avahi = {
            enable = lib.mkForce true;
            nssmdns4 = true;
            publish = {
              enable = true;
              addresses = true;
            };
          };

          # agetty expands \n (hostname) and \4 (IPv4) and redraws the prompt
          # when addresses change, so this stays correct after DHCP.
          services.getty.helpLine = ''

            SSH: root@\n.local  (\4)
          '';

          time.timeZone = "Europe/Berlin";
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
