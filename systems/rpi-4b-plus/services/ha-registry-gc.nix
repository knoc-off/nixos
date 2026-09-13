# Entity registry GC for the sun-follow MQTT entities.
#
# Home Assistant never removes YAML-configured MQTT entities from its entity
# registry. When one disappears from the config, `__async_remove_impl`
# (helpers/entity.py) calls `write_unavailable_state()` and *keeps the row* --
# the 30-day orphan purge only covers rows that were already explicitly
# deleted. So every `unique_id` we stop generating lingers forever as an
# `unavailable` entity, and worse, squats the good entity_id: its live
# replacement gets registered as `..._2`.
#
# unique_id is now keyed on the IEEE address (see mqtt-automations/default.nix)
# so renames no longer churn identity, but the orphans from before that change
# still need clearing, and a device genuinely removed from the registry should
# not leave debris behind either.
#
# This runs *before* home-assistant starts, so it edits .storage while HA is
# stopped -- HA loads the registry at startup and rewrites it from memory, so
# editing underneath a running instance would simply be overwritten.
#
# Scope is deliberately narrow: only entities whose unique_id starts with
# `sun_follow_` and devices identified as `sun-follow-*`. Everything else
# (zigbee2mqtt discovery, mobile_app, ...) is owned by something else and is
# never touched.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  haConfig = config.services.home-assistant.config;

  mqttEntities =
    (haConfig.mqtt.switch or [ ])
    ++ (haConfig.mqtt.number or [ ])
    ++ (haConfig.mqtt.button or [ ])
    ++ (haConfig.mqtt.sensor or [ ]);

  sunFollowEntities = builtins.filter (e: lib.hasPrefix "sun_follow_" e.unique_id) mqttEntities;

  # Both halves of the desired state are emitted explicitly rather than having
  # the script recover device ids by string-splitting unique_ids -- that
  # coupling would break silently the first time either naming scheme changed.
  desiredFile = (pkgs.formats.json { }).generate "ha-sun-follow-desired.json" {
    entities = map (e: e.unique_id) sunFollowEntities;
    devices = lib.unique (
      builtins.concatMap (e: e.device.identifiers or [ ]) sunFollowEntities
    );
  };

  gc = pkgs.writeShellApplication {
    name = "ha-registry-gc";
    runtimeInputs = with pkgs; [ jq ];
    # The jq filters below are single-quoted on purpose: `$d`/`$want` are jq
    # variables bound via --slurpfile, not shell expansions.
    excludeShellChecks = [ "SC2016" ];
    text = ''
      storage="''${HASS_STORAGE:-/var/lib/hass/.storage}"
      entities="$storage/core.entity_registry"
      devices="$storage/core.device_registry"
      desired="${desiredFile}"

      [ -f "$entities" ] || { echo "no entity registry yet, nothing to do"; exit 0; }

      # Rewrites go through a temp file, are validated, then moved into place,
      # so an interrupted or malformed run can never leave HA with a truncated
      # registry to load.
      rewrite() {
        local target="$1" filter="$2" guard="$3" what="$4"
        local tmp before after
        tmp=$(mktemp)
        jq --slurpfile d "$desired" "$filter" "$target" > "$tmp"
        jq -e "$guard" "$tmp" >/dev/null

        before=$(jq "$guard | length" "$target")
        after=$(jq "$guard | length" "$tmp")
        if [ "$before" -eq "$after" ]; then
          rm -f "$tmp"
          echo "$what registry clean"
          return 0
        fi

        echo "removing $((before - after)) stale $what entr(y|ies)"
        chown --reference="$target" "$tmp"
        chmod --reference="$target" "$tmp"
        mv "$tmp" "$target"
      }

      # Report what goes before it goes, so the journal says which entities
      # were dropped rather than just a count.
      jq -r --slurpfile d "$desired" '
        ($d[0].entities | map({(.): true}) | add // {}) as $want
        | .data.entities[]
        | select((.unique_id | type) == "string")
        | select(.unique_id | startswith("sun_follow_"))
        | select($want[.unique_id] // false | not)
        | "  stale entity: \(.entity_id)  <=  \(.unique_id)"
      ' "$entities"

      rewrite "$entities" '
        ($d[0].entities | map({(.): true}) | add // {}) as $want
        | .data.entities |= map(
            select(
              ((.unique_id | type) != "string")
              or (.unique_id | startswith("sun_follow_") | not)
              or ($want[.unique_id] // false)
            )
          )
      ' '.data.entities' "entity"

      [ -f "$devices" ] || exit 0

      rewrite "$devices" '
        ($d[0].devices | map({(.): true}) | add // {}) as $want
        | .data.devices |= map(
            select(
              ([.identifiers // [] | flatten[] | select(type == "string" and startswith("sun-follow-"))] | length) == 0
              or ([.identifiers | flatten[] | select(type == "string" and startswith("sun-follow-")) | select($want[.] // false)] | length) > 0
            )
          )
      ' '.data.devices' "device"
    '';
  };
in
{
  systemd.services.ha-registry-gc = {
    description = "Remove orphaned sun-follow entities from the Home Assistant registry";
    # Before, not after: HA reads the registry at startup and rewrites it from
    # memory, so anything changed under a running instance is discarded.
    before = [ "home-assistant.service" ];
    requiredBy = [ "home-assistant.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe gc;
      RemainAfterExit = false;
    };
  };
}
