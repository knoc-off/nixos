# Optiplex as build farm + binary cache for the rest of the tailnet.
#
# Three independent switches, meant to be mixed per host:
#
#   server   -- harmonia + a nixremote login, for optiplex only.
#   client   -- substituter pointed at optiplex.
#   builder  -- dispatch builds to optiplex over ssh-ng.
#
# client and builder are separate because they answer different questions
# ("where do I fetch already-built things from" vs "where do I ask to build
# things I don't have") and a host could plausibly want one without the
# other. In practice every non-optiplex, non-nuci5 host wants both.
{ self, ... }:
let
  inherit (self.lib) ssh;
  inherit (self.lib.tailnet) optiplex;

  port = 5000;

  # Filled in after the first server deploy: `journalctl -u harmonia-init` (or
  # `cat /var/lib/harmonia/cache.key` and derive the public half) prints it.
  # Deliberately not a real key so a half-finished bootstrap fails loudly
  # (wrong signature) instead of silently trusting an unsigned cache.
  cachePublicKey = "optiplex-1:0000000000000000000000000000000000000000=";

  cacheUrl = "http://${optiplex}:${toString port}";
in
{
  nixos =
    {
      config,
      lib,
      pkgs,
      hostname,
      ...
    }:
    let
      cfg = config.services.nixCache;
    in
    {
      options.services.nixCache = {
        server.enable = lib.mkEnableOption "harmonia binary cache, serving this host's /nix/store over the tailnet";
        client.enable = lib.mkEnableOption "optiplex as an extra substituter";
        builder.enable = lib.mkEnableOption "optiplex as a distributed build machine";
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.server.enable {
          assertions = [
            {
              assertion = cachePublicKey != "optiplex-1:0000000000000000000000000000000000000000=";
              message = "modules/nix-cache.nix: cachePublicKey is still the bootstrap placeholder. Fill it in from the real key (see harmonia-init.service) before relying on client.enable elsewhere.";
            }
          ];

          services.harmonia.cache = {
            enable = true;
            # Module default is 50, cache.nixos.org is 40 -- without this,
            # clients would consult upstream first and optiplex never wins.
            settings.priority = 30;
            signKeyPaths = [ "/var/lib/harmonia/cache.key" ];
          };

          # bind stays at the module default ([::]:5000): the systemd socket
          # unit derives its ListenStream from cache.settings.bind, and
          # binding the tailnet IP directly would fail at boot, before
          # tailscaled has brought the interface up. Confinement comes from
          # the firewall rule below instead.
          networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ port ];

          systemd.services.harmonia-init = {
            description = "Generate the harmonia cache signing key";
            wantedBy = [ "harmonia.service" ];
            before = [ "harmonia.service" ];
            unitConfig.ConditionPathExists = "!/var/lib/harmonia/cache.key";
            serviceConfig = {
              Type = "oneshot";
              StateDirectory = "harmonia";
              ExecStart = pkgs.writeShellScript "harmonia-init" ''
                ${config.nix.package}/bin/nix-store --generate-binary-cache-key optiplex-1 \
                  /var/lib/harmonia/cache.key /var/lib/harmonia/cache.pub
                echo "harmonia cache public key: $(cat /var/lib/harmonia/cache.pub)"
              '';
            };
          };

          users.users.nixremote = {
            isSystemUser = true;
            group = "nixremote";
            # The isSystemUser default (pkgs.shadow -> nologin) would refuse to
            # run the forced command below at all; sshd execs the login shell
            # with `-c command`, so it has to be a real shell.
            shell = pkgs.bash;

            openssh.authorizedKeys.keys =
              let
                # Every host that's a client of the cache is also a builder
                # client, so its host key needs to log in here as nixremote.
                # optiplex itself and nuci5 (no tailnet) are never in this list.
                builderHosts = [
                  "framework13"
                  "thinkpad-work"
                  "hetzner"
                  "rpi-4b-plus"
                ];
                forced = key: ''command="${config.nix.package}/bin/nix-daemon --stdio",restrict ${key}'';
              in
              map (h: forced ssh.hostKeys.${h}) (
                builtins.filter (h: ssh.hostKeys.${h} != "") builderHosts
              );
          };
          users.groups.nixremote = { };
          nix.settings.trusted-users = [ "nixremote" ];
        })

        (lib.mkIf cfg.client.enable {
          assertions = [
            {
              assertion = hostname != "optiplex";
              message = "modules/nix-cache.nix: services.nixCache.client should not be enabled on optiplex itself -- it would consult its own cache and defeat --skip-cached during autobuild.";
            }
          ];

          nix.settings = {
            extra-substituters = [ cacheUrl ];
            extra-trusted-public-keys = [ cachePublicKey ];
            # Defaults are fallback = false and connect-timeout = 15s: an
            # offline optiplex would otherwise turn every build into a hard
            # error instead of a slower local build.
            fallback = true;
            connect-timeout = lib.mkDefault 5;
          };
        })

        (lib.mkIf cfg.builder.enable {
          assertions = [
            {
              assertion = ssh.hostKeys.${hostname} or "" != "";
              message = "modules/nix-cache.nix: services.nixCache.builder needs lib.ssh.hostKeys.${hostname} filled in (ssh-keyscan -t ed25519 <host>) so optiplex can be told which client keys to trust, and so this host can verify optiplex in known_hosts.";
            }
          ];

          nix.distributedBuilds = true;
          nix.settings.builders-use-substitutes = true;

          nix.buildMachines = [
            {
              hostName = optiplex;
              protocol = "ssh-ng";
              sshUser = "nixremote";
              sshKey = "/etc/ssh/ssh_host_ed25519_key";
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
          ];

          # publicHostKey (base64 -w0 of the .pub file) is left unset -- optiplex
          # is verified the ordinary way instead, via known_hosts. Avoids an
          # extra IFD-computed base64 encode for what programs.ssh already does.
          programs.ssh.knownHosts.optiplex = {
            hostNames = [ optiplex ];
            publicKey = ssh.hostKeys.optiplex;
          };
        })
      ];
    };
}
