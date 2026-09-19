# Align Home Assistant entity_ids with the device registry.
#
# HA anchors an entity_id at first discovery and never revisits it, so a
# zigbee2mqtt rename leaves the old id behind: the living room light stays
# `light.light_1` long after its friendly_name became `livingroom_light`.
# That is what forced the dashboard to carry a hand-maintained IEEE ->
# entity_id table; once this has run, `light.${device.name}` is just correct
# and the table is unnecessary.
#
# Why a service and not an offline .storage edit like ha-registry-gc:
# recorder migrates a rename's history only when it observes
# EVENT_ENTITY_REGISTRY_UPDATED (components/recorder/entity_registry.py,
# `_async_entity_id_changed`). A direct JSON edit fires no event, so every
# entity's history would be stranded under its old id. The rename has to go
# through the running instance's API.
#
# Scope is every entity zigbee2mqtt owns for a device declared in devices.nix,
# primary and secondary alike, so `sensor.livingroom_plug_1_power` follows the
# device name too. The z2m bridge's own entities and anything not in the
# registry are left alone. See ha-entity-rename.py for the matching rule.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../devices.nix) allDevices;

  # IEEE -> desired device name. The script derives every entity_id from
  # this: `<domain>.<name>` for a device's primary entity and
  # `<domain>.<name>_<suffix>` for its secondaries.
  wanted = builtins.listToAttrs (
    map (d: lib.nameValuePair d.id d.name) allDevices
  );

  wantedFile = (pkgs.formats.json { }).generate "ha-entity-renames.json" wanted;

  rename = pkgs.writers.writePython3Bin "ha-entity-rename"
    {
      libraries = [ pkgs.python3Packages.websockets ];
      # The script is checked by the test suite in this directory, and
      # flake8's line-length/complexity opinions aren't worth reflowing it for.
      flakeIgnore = [
        "E501"
        "W503"
      ];
    }
    (builtins.readFile ./ha-entity-rename.py);
in
{
  sops.secrets."home-assist/accesstoken" = { };

  systemd.services.ha-entity-rename = {
    description = "Align Home Assistant entity_ids with the device registry";
    # After, not before: the rename must go through the running instance so
    # recorder sees the registry event and migrates history along with it.
    after = [ "home-assistant.service" ];
    wants = [ "home-assistant.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HA_URL = "ws://127.0.0.1:${toString config.services.home-assistant.config.http.server_port}/api/websocket";
      RENAMES_FILE = wantedFile;
      TOKEN_FILE = "%d/token";
    };

    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe rename;
      # HA's websocket API only starts answering some way after the unit goes
      # active, so a first attempt can legitimately lose the race. Retry
      # rather than ordering on something that doesn't exist.
      Restart = "on-failure";
      RestartSec = 30;
      DynamicUser = true;
      LoadCredential = [ "token:${config.sops.secrets."home-assist/accesstoken".path}" ];
    };
  };
}
