{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    inputs.nix-minecraft.nixosModules.minecraft-servers
  ];

  nixpkgs.overlays = [inputs.nix-minecraft.overlay];
  nixpkgs.config.allowUnfree = true;

  services.minecraft-servers = {
    eula = true;
    enable = true;
    servers.beez = {
      autoStart = false;
      package = pkgs.fabricServers.fabric-1_21_1;
      jvmOpts = "-Xmx8G -Xms8G";
      enable = true;
      serverProperties = {
        server-port = 25565;
        difficulty = 3;
        motd = "minecraft";
        spawn-protection = 0;

        # Rcon
        enable-rcon = true;
        "rcon.password" = "123"; # doesnt have to be secure, local only
        "rcon.port" = 25570;
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

  services.logind = {
    extraConfig = ''
      HandleLidSwitch=ignore
      HandleLidSwitchDocked=ignore
    '';
  };

  networking = {
    firewall = {
      allowedUDPPorts = [ 25565 ];
      allowedTCPPorts = [ 25565 ];
    };
  };
}
