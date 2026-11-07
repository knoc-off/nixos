{
  inputs,
  self,
  pkgs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;
  user = "nixos";
in
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
    {
      wsl = {
        enable = true;
        defaultUser = user;
        # Windows tools (powershell.exe, reg.exe, explorer.exe) on PATH, so
        # the agent can reach the Windows side without ssh. Both are the
        # module defaults; set explicitly because opencode-remote's context
        # file relies on them.
        interop.register = true;
        interop.includePath = true;
      };
    }

    # Substitute from optiplex so opencode-remote and friends are never built
    # here. Only `client`: dispatching builds would need this host's ssh key
    # in lib/ssh.nix, which a WSL install doesn't have up front.
    self.nixosModules.nix-cache
    { services.nixCache.client.enable = true; }

    # Jev key (/run/secrets/jev/api-key) for opencode-remote's jev-review and
    # search tools, plus the `jegrep` CLI they run.
    self.nixosModules.sops
    self.nixosModules.jegrep
  ];

  # Joins the tailnet by hand rather than through services.tailnet, which
  # needs a sops-decryptable host key before first boot (see README):
  #   sudo tailscale up --login-server=https://headscale.niko.ink
  # then approve the node in headscale. optiplex's /ai-raw is tailnet-only.
  services.tailscale.enable = true;

  # Deployed from framework13 over the tailnet, so the private git+ssh input
  # is evaluated and built there, never here:
  #   nixos-rebuild switch --flake .#wsl --target-host root@wsl
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];
  users.users.root.openssh.authorizedKeys.keys = [ self.lib.ssh.user.framework13 ];

  environment.systemPackages = [
    self.packages.${system}.opencode-remote
    pkgs.git
    pkgs.ripgrep
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  time.timeZone = "Europe/Berlin";

  system.stateVersion = "26.05";
}
