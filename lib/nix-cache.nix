# The build farm / binary cache: which host runs it, and who's allowed to
# use it. Consumed by modules/nix-cache.nix, which stays host-agnostic and
# only ever reads from here -- swapping build farms means editing this file,
# not the module.
{
  # Which host in lib.tailnet runs harmonia + accepts distributed builds.
  hostName = "optiplex";
  port = 5000;

  # Passed to `nix-store --generate-binary-cache-key`. Only the name half is
  # fixed here; see publicKey below for the key itself.
  keyName = "optiplex-1";

  # Harmonia's signing public key, printed by harmonia-init.service (or
  # `cat /var/lib/harmonia/cache.pub`) on first boot of the server. Empty
  # string = not yet bootstrapped; modules/nix-cache.nix fails loudly on
  # client.enable rather than silently trusting an unsigned cache.
  publicKey = "optiplex-1:Tfd4+AJqqEfEdnmXOk+71AehkBBgm3oHx4W2wJRtev8=";

  # Hosts allowed to authenticate to the server as `nixremote` (i.e. every
  # host that runs services.nixCache.builder). Driven off lib.ssh.hostKeys,
  # so a host only actually gets in once its own key is filled in there.
  clients = [
    "framework13"
    "thinkpad-work"
    "hetzner"
    "rpi-4b-plus"
  ];

  # nix.buildMachines tuning for the server.
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];
  maxJobs = 8;
  speedFactor = 2;
  supportedFeatures = [
    "kvm"
    "big-parallel"
    "nixos-test"
    "benchmark"
  ];
}
