# Headscale-assigned tailnet addresses, by host.
#
# Single source of truth. hetzner's Gate backend, optiplex's firewall rule and
# headscale's MagicDNS extra_records must all agree; a mismatch there is a
# silent outage rather than an eval error, so they all read from here.
#
# These are literal IPs rather than MagicDNS names deliberately:
#
#   - Server hosts set services.tailnet.acceptDns = false (modules/tailnet.nix)
#     so they keep resolving LAN names and their own services locally. They
#     cannot resolve *.tail.niko.ink at all.
#   - The optiplex firewall rule is handed to iptables, which resolves names
#     once at rule-insertion time during early boot -- before tailscale is up.
#     A name there would fail the lookup and take firewall.service down with it.
#
# Headscale allocates from 100.64.0.0/10 in registration order, so these are not
# guessable from the host list -- confirm against `headscale nodes list`.
# Verified 2026-08-08. Only the NixOS hosts in this flake are listed; phones and
# other clients are addressed by MagicDNS from the client side.
{
  # "oink" in headscale, `hetzner` in this flake.
  hetzner = "100.64.0.1";
  rpi-4b-plus = "100.64.0.2";
  framework13 = "100.64.0.3";
  optiplex = "100.64.0.7";
}
