# Rooms for services.lighting (modules/lighting.nix): each room's bulbs come
# from the device registry, and its behaviour -- a state machine -- from
# `<room>.lua` next to this file. The format and helpers:
# pkgs/mqtt-automations/src/prelude.lua.
{
  lib,
  self,
  ...
}:
let
  inherit (import ../../devices.nix) lit kinds zigbeeGroups rooms;

  groupOf =
    roomKey: lib.findFirst (g: zigbeeGroups.${g}.room == roomKey) null (builtins.attrNames zigbeeGroups);

  room = roomKey: {
    bulbs = lib.mapAttrs (_: d: {
      device = d.name;
      dimmable = d.kind == kinds.light;
    }) lit.${roomKey};
    group = groupOf roomKey;
    inherit (rooms.${roomKey}) label;
    lua = builtins.readFile ./${roomKey}.lua;
  };
in
{
  imports = [
    self.nixosModules.lighting
    ./home-assistant.nix
  ];

  services.lighting = {
    enable = true;
    latitude = 52.52;
    longitude = 13.405;
    rooms = lib.genAttrs [
      "living-room"
      "kitchen"
      "bedroom"
      "bathroom"
      "hallway"
      "cupboard"
    ] room;
  };
}
