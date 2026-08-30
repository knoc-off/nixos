# Build farm + binary cache for the tailnet. Fully generic: which host runs
# the server and who's allowed to use it live in lib/nix-cache.nix, not here.
#
# Three independent switches, meant to be mixed per host:
#
#   server   -- harmonia + a nixremote login, for the cache host.
#   client   -- the cache host as an extra substituter.
#   builder  -- dispatch builds to the cache host over ssh-ng.
#
# client and builder are separate because they answer different questions
# ("where do I fetch already-built things from" vs "where do I ask to build
# things I don't have") and a host could plausibly want one without the
# other. In practice every client in cache.clients wants both.
{ self, ... }:
let
  inherit (self.lib) ssh;
  cache = self.lib.nixCache;
  cacheHost = self.lib.tailnet.${cache.hostName};

  cacheUrl = "http://${cacheHost}:${toString cache.port}";
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
        server.enable = lib.mkEnableOption "harmonia binary cache + distributed-build server, for the cache host itself";
        client.enable = lib.mkEnableOption "the cache host as an extra substituter";
        builder.enable = lib.mkEnableOption "the cache host as a distributed build machine";
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.server.enable {
          services.harmonia.cache = {
            enable = true;
            # Module default is 50, cache.nixos.org is 40 -- without this,
            # clients would consult upstream first and this cache never wins.
            settings.priority = 30;
            signKeyPaths = [ "/var/lib/harmonia/cache.key" ];
          };

          # bind stays at the module default ([::]:5000): the systemd socket
          # unit derives its ListenStream from cache.settings.bind, and
          # binding the tailnet IP directly would fail at boot, before
          # tailscaled has brought the interface up. Confinement comes from
          # the firewall rule below instead.
          networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cache.port ];

          systemd.services.harmonia-init = {
            description = "Generate the harmonia cache signing key";
            wantedBy = [ "harmonia.service" ];
            before = [ "harmonia.service" ];
            unitConfig.ConditionPathExists = "!/var/lib/harmonia/cache.key";
            serviceConfig = {
              Type = "oneshot";
              StateDirectory = "harmonia";
              ExecStart = pkgs.writeShellScript "harmonia-init" ''
                ${config.nix.package}/bin/nix-store --generate-binary-cache-key ${cache.keyName} \
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
                forced = key: ''command="${config.nix.package}/bin/nix-daemon --stdio",restrict ${key}'';
              in
              map (h: forced ssh.hostKeys.${h}) (builtins.filter (h: ssh.hostKeys.${h} != "") cache.clients);
          };
          users.groups.nixremote = { };
          nix.settings.trusted-users = [ "nixremote" ];
        })

        (lib.mkIf cfg.client.enable {
          assertions = [
            {
              assertion = hostname != cache.hostName;
              message = "modules/nix-cache.nix: services.nixCache.client should not be enabled on the cache host itself -- it would consult its own cache and defeat --skip-cached during autobuild.";
            }
            {
              assertion = cache.publicKey != "";
              message = "modules/nix-cache.nix: lib.nixCache.publicKey is still empty. Fill it in from the real key (see harmonia-init.service on ${cache.hostName}) before relying on client.enable.";
            }
          ];

          nix.settings = {
            extra-substituters = [ cacheUrl ];
            extra-trusted-public-keys = [ cache.publicKey ];
            # Defaults are fallback = false and connect-timeout = 15s: an
            # offline cache host would otherwise turn every build into a hard
            # error instead of a slower local build.
            fallback = true;
            connect-timeout = lib.mkDefault 5;
          };
        })

        (lib.mkIf cfg.builder.enable {
          assertions = [
            {
              assertion = ssh.hostKeys.${hostname} or "" != "";
              message = "modules/nix-cache.nix: services.nixCache.builder needs lib.ssh.hostKeys.${hostname} filled in (ssh-keyscan -t ed25519 <host>) so ${cache.hostName} can be told which client keys to trust, and so this host can verify ${cache.hostName} in known_hosts.";
            }
            {
              assertion = ssh.hostKeys.${cache.hostName} != "";
              message = "modules/nix-cache.nix: services.nixCache.builder needs lib.ssh.hostKeys.${cache.hostName} filled in (ssh-keyscan -t ed25519 ${cache.hostName}) so this host can verify ${cache.hostName}'s known_hosts entry -- otherwise programs.ssh accepts the empty string as a valid publicKey and known_hosts ends up silently broken.";
            }
          ];

          nix.distributedBuilds = true;
          nix.settings.builders-use-substitutes = true;

          nix.buildMachines = [
            {
              hostName = cacheHost;
              protocol = "ssh-ng";
              sshUser = "nixremote";
              sshKey = "/etc/ssh/ssh_host_ed25519_key";
              inherit (cache)
                systems
                maxJobs
                speedFactor
                supportedFeatures
                ;
            }
          ];

          # publicHostKey (base64 -w0 of the .pub file) is left unset -- the
          # cache host is verified the ordinary way instead, via known_hosts.
          # Avoids an extra IFD-computed base64 encode for what programs.ssh
          # already does.
          programs.ssh.knownHosts.${cache.hostName} = {
            hostNames = [ cacheHost ];
            publicKey = ssh.hostKeys.${cache.hostName};
          };
        })
      ];
    };
}
