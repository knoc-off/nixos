# SSH public keys, split by what the key *is*.
#
#   user     -- the keys I log in with, from my own agent/~/.ssh.
#   hostKeys -- each machine's /etc/ssh/ssh_host_ed25519_key.pub.
#
# The two are not interchangeable. hostKeys identify the *machine*, and are what
# the distributed-build setup uses: a client's nix-daemon runs as root and
# authenticates to optiplex's `nixremote` account with the client's own host key
# (nix.buildMachines.sshKey = /etc/ssh/ssh_host_ed25519_key), while clients
# verify optiplex via programs.ssh.knownHosts. No extra keypair to distribute,
# and revoking a host is a one-line deletion here.
#
# Collect with: ssh-keyscan -t ed25519 <host-or-tailnet-ip>
{
  user = {
    # hetzner =
    # rpi-4b-plus =
    # nuci5 =
    framework13 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJojYXf9Koo8FT/vWB+skUbrgWCkng158wJvHX0zJBXb selby@niko.ink";
    thinkpad-work = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAoc9pt7DrD5G0RYHRcyZv7QCBocoy1O0lKUtsikF5NH nicholas.selby@nelly-solutions.com";
    # optiplex =
  };

  # Root host keys. Empty string = not yet collected; modules/nix-cache.nix
  # filters those out rather than emitting a broken authorized_keys line, so
  # this can be filled in host by host.
  hostKeys = {
    optiplex = "";
    framework13 = "";
    thinkpad-work = "";
    hetzner = "";
    rpi-4b-plus = "";
  };
}
