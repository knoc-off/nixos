{ inputs, self, lib, pkgs, config, ... }: {
  imports = [

    inputs.nix-minecraft.nixosModules.minecraft-servers
    ./minecraft-gate-reverse-proxy.nix
  ];

  nixpkgs.overlays = [ inputs.nix-minecraft.overlay ];
  nixpkgs.config.allowUnfree = true;

  # add a as a package to the system
  environment.systemPackages = [
    (let
      generateRconConfig = serverName: server: {
        "${serverName}" = {
          address = "127.0.0.1:${toString server.serverProperties."rcon.port"}";
          port = server.serverProperties."rcon.port";
          password = server.serverProperties."rcon.password";
          timeout = "10s";
          type = "rcon";
        };
      };

      rconConfigs = lib.head (lib.mapAttrsToList
        (serverName: server: generateRconConfig serverName server)
        config.services.minecraft-servers.servers);

      rconFile = pkgs.writeTextFile {
        name = "rcon.yaml";
        text = pkgs.lib.generators.toYAML { } rconConfigs;
      };

    in pkgs.writeShellScriptBin "mcrcon" ''
      ${
        self.packages.${pkgs.system}.rcon-cli
      }/bin/gorcon --config ${rconFile} -e $@
    '')
  ];

  services.gateService = {
    enable = false;
    config = {
      lite = {
        enabled = true;
        routes = lib.mapAttrsToList (serverName: server: {
          host = "${serverName}.kobbl.co";
          backend =
            "localhost:${toString server.serverProperties."server-port"}";
        }) config.services.minecraft-servers.servers ++ [{ # custom routes
          host = "kobbl.co";
          backend = "localhost:25500";
        }];
      };
    };
  };

  services.minecraft-servers = {
    eula = true;
    enable = true;
    # this server declaration, should be added in the system that calls the module.
    # that would allow this to be more modular and allow for multiple servers to be defined.
    servers.beez = {
      autoStart = false;
      package = pkgs.fabricServers.fabric-1_21_1;
      jvmOpts = "-Xmx8G -Xms8G";
      enable = true;
      serverProperties = {
        server-port = 25565;
        difficulty = 3; # 0: peaceful, 1: easy, 2: normal, 3: hard
        motd = "minecraft";
        spawn-protection = 0;

        # Rcon
        enable-rcon = true;
        "rcon.password" = "123"; # doesnt have to be secure, local only
        "rcon.port" = 25570;
        # connect to rcon with `rcon -H localhost -p 25570 -P 123`
      };
      symlinks = {
        "ops.json" = pkgs.writeTextFile {
          name = "ops.json";
          text = ''
            [
              {
                "uuid": "c9e17620-4cc1-4d83-a30a-ef320cc099e6",
                "name": "knoc_off",
                "level": 4,
                "bypassesplayerlimit": true
              }
            ]
          '';
        };
      };
    };
  };

  # create an rcon script for each of the config.sercices.minecraft-servers.servers
  # so that you can run `rcon <server>` to connect to the server, IE: `rcon beez`

  networking = {
    firewall = {
      allowedUDPPorts = [ 25565 ];
      allowedTCPPorts = [ 25565 ];
    };
  };
}
