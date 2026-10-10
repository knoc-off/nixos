# Every light in the house from one process: the `lights` binary from
# pkgs/mqtt-automations. Each room is a Lua script (API: src/script.rs,
# helpers: src/prelude.lua) deciding what the room wants; a per-bulb arbiter
# in Rust decides whether the bulb listens or a person is in charge.
#
# The generated config is loaded with `lights --check` at build time, so a
# script that fails to load (syntax error, unknown bulb, bad option) fails
# the rebuild instead of the service.
{ self, ... }:
{
  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (lib) mkEnableOption mkOption mkIf types;
      cfg = config.services.lighting;

      configJson = (pkgs.formats.json { }).generate "lights.json" {
        inherit (cfg) latitude longitude;
        rooms = lib.mapAttrs (_: room: {
          inherit (room) group lua;
          bulbs = lib.mapAttrs (_: b: { inherit (b) device dimmable; }) room.bulbs;
        }) cfg.rooms;
      };

      checkedConfig = pkgs.runCommand "lights-checked.json" { } ''
        ${lib.getExe' cfg.package "lights"} --check ${configJson}
        cp ${configJson} $out
      '';
    in
    {
      options.services.lighting = {
        enable = mkEnableOption "the `lights` room and bulb automation";

        package = mkOption {
          type = types.package;
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.mqtt-automations;
          description = "Package providing the `lights` binary.";
        };

        latitude = mkOption {
          type = types.float;
          description = "Location for the sun curves.";
        };

        longitude = mkOption {
          type = types.float;
          description = "Location for the sun curves.";
        };

        rooms = mkOption {
          default = { };
          description = "Rooms, each with its bulbs and the script that drives them.";
          type = types.attrsOf (
            types.submodule {
              options = {
                bulbs = mkOption {
                  description = "Bulbs and plugs this room owns, by the name the script uses.";
                  type = types.attrsOf (
                    types.submodule {
                      options = {
                        device = mkOption {
                          type = types.str;
                          description = "zigbee2mqtt friendly name.";
                        };
                        dimmable = mkOption {
                          type = types.bool;
                          default = true;
                          description = "False for plugs: on/off only.";
                        };
                      };
                    }
                  );
                };
                group = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = ''
                    zigbee2mqtt group containing exactly this room's bulbs. A
                    change that is the same for every bulb then goes out as
                    one group command, so the bulbs switch together.
                  '';
                };
                lua = mkOption {
                  type = types.lines;
                  description = "The room's script.";
                };
              };
            }
          );
        };
      };

      config = mkIf cfg.enable {
        systemd.services.lights = {
          description = "Room lighting automation";
          after = [
            "mosquitto.service"
            "network-online.target"
          ];
          wants = [
            "mosquitto.service"
            "network-online.target"
          ];
          wantedBy = [ "multi-user.target" ];
          environment.CONFIG = checkedConfig;
          serviceConfig = {
            ExecStart = lib.getExe' cfg.package "lights";
            Restart = "always";
            RestartSec = "10s";
            DynamicUser = true;
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
          };
          unitConfig = {
            StartLimitIntervalSec = 300;
            StartLimitBurst = 20;
          };
        };
      };
    };
}
