# sops-nix scaffolding common to every secret-having host: the module
# import and the age key path (always the host's own ssh host key). Each
# host still sets its own `sops.defaultSopsFile = ./secrets.yaml;` and
# `sops.secrets = {...};` -- those are genuinely host-local, not shared.
{ inputs, ... }:
{
  nixos =
    { lib, ... }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];
      sops.age.sshKeyPaths = lib.mkDefault [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
}
