# Declarative zigbee2mqtt group membership and button binds.
#
# z2m removed `groups.<id>.devices` from configuration.yaml in settings
# version 2, so group membership can only be set at runtime through the
# bridge request API. This reconciles the live state against ../devices.nix
# after every z2m start, which gets the declarative behaviour back without
# fighting z2m over the config file.
#
# Add-only by design: members present on the device but absent from the
# registry are reported and left alone, so adding a device through the z2m
# frontend isn't silently reverted on the next restart. Flip to strict
# reconciliation only if the frontend stops being used for this.
{
  lib,
  pkgs,
  ...
}:
let
  inherit (import ../devices.nix) zigbeeGroups;

  # Desired state as JSON, so the script diffs data instead of having the
  # device list baked into generated shell.
  desiredFile = (pkgs.formats.json { }).generate "z2m-groups-desired.json" (
    lib.mapAttrsToList (gName: g: {
      group = gName;
      group_id = g.id;
      members = map (d: d.name) g.members;
      binds = lib.optional (g ? bind) {
        from = g.bind.from.name;
        clusters = g.bind.clusters;
      };
    }) zigbeeGroups
  );

  reconcile = pkgs.writeShellApplication {
    name = "z2m-groups-reconcile";
    runtimeInputs = with pkgs; [
      mosquitto
      jq
    ];
    text = ''
      broker="''${MQTT_HOST:-localhost}"
      base="''${Z2M_BASE_TOPIC:-zigbee2mqtt}"
      desired="${desiredFile}"

      # Publish a bridge request and block until its matching response
      # arrives, so a failure (device asleep, unreachable, bad payload) fails
      # the unit instead of vanishing. z2m echoes back the `transaction` field
      # it was given, which is what makes the correlation reliable -- without
      # it a concurrent request's response could be mistaken for ours.
      #
      # The subscriber starts *before* the publish: z2m is fast enough to
      # answer before a subscribe issued afterwards would be established.
      txn=0
      request() {
        local kind="$1" payload="$2" resp
        txn=$((txn + 1))
        local id="z2m-groups-$$-$txn"

        exec {respfd}< <(
          mosquitto_sub -h "$broker" -t "$base/bridge/response/$kind" \
            -C 1 -W "''${REQUEST_TIMEOUT:-60}" 2>/dev/null
        )
        # Give the subscription a moment to be established before publishing.
        sleep 0.5
        mosquitto_pub -h "$broker" -t "$base/bridge/request/$kind" \
          -m "$(jq -nc --argjson p "$payload" --arg t "$id" '$p + {transaction: $t}')"

        resp=$(cat <&$respfd)
        exec {respfd}<&-

        if [ -z "$resp" ]; then
          echo "  timed out waiting for response to $kind" >&2
          return 1
        fi
        # Requests are issued serially and nothing else should be driving the
        # bridge, so the first response is ours -- verify that rather than
        # assume it, since a mismatch means a concurrent client and a result
        # that can't be trusted.
        if [ "$(jq -r '.transaction // ""' <<<"$resp")" != "$id" ]; then
          echo "  unexpected response (not transaction $id): $resp" >&2
          return 1
        fi
        if ! jq -e '.status == "ok"' <<<"$resp" >/dev/null; then
          echo "  failed: $(jq -r '.error // "unknown error"' <<<"$resp")" >&2
          return 1
        fi
        return 0
      }

      # Retained topic, so this returns immediately once z2m is up. The unit
      # is ordered after zigbee2mqtt.service, but systemd considers the unit
      # started as soon as the process forks -- z2m still has to connect to
      # the adapter and MQTT after that, hence the wait rather than a plain
      # read.
      echo "waiting for z2m to come online..."
      state=$(mosquitto_sub -h "$broker" -t "$base/bridge/state" -C 1 -W "''${ONLINE_TIMEOUT:-120}")
      if ! jq -e '.state == "online"' <<<"$state" >/dev/null; then
        echo "z2m is not online: $state" >&2
        exit 1
      fi

      # Both retained: current group membership and per-device bindings.
      groups=$(mosquitto_sub -h "$broker" -t "$base/bridge/groups" -C 1 -W 30)
      devices=$(mosquitto_sub -h "$broker" -t "$base/bridge/devices" -C 1 -W 30)

      rc=0

      # Members to add: desired minus live. Live membership is reported as
      # ieee_address, so map it back through bridge/devices to friendly
      # names. `$live` is collected with [] rather than bound from a stream
      # so a group that doesn't exist yet yields an empty array instead of an
      # empty stream -- the latter silently swallows the whole pipeline,
      # which is exactly the state on first run.
      while read -r group device; do
        echo "adding '$device' to group '$group'"
        request "group/members/add" \
          "$(jq -nc --arg g "$group" --arg d "$device" '{group: $g, device: $d}')" || rc=1
      done < <(
        jq -r --argjson groups "$groups" --argjson devices "$devices" '
          ($devices | map({key: .ieee_address, value: .friendly_name}) | from_entries) as $names
          | .[]
          | .group as $group
          | [ $groups[] | select(.friendly_name == $group) | .members[]
              | $names[.ieee_address] // .ieee_address ] as $live
          | (.members - $live)[]
          | "\($group) \(.)"
        ' "$desired"
      ) || rc=1

      # Extra members are reported, not removed -- see the header.
      jq -r --argjson groups "$groups" --argjson devices "$devices" '
        ($devices | map({key: .ieee_address, value: .friendly_name}) | from_entries) as $names
        | .[]
        | .group as $group
        | .members as $want
        | [ $groups[] | select(.friendly_name == $group) | .members[]
            | $names[.ieee_address] // .ieee_address ] as $live
        | ($live - $want)[]
        | "note: \(.) is in group \($group) but not in the registry (left alone)"
      ' "$desired"

      # Binds: only those already targeting this group count as satisfied.
      # Coordinator binds (reporting) have target.type == "endpoint" and are
      # none of our business.
      #
      # A bind failure does NOT fail the unit. Binds target battery-powered
      # buttons, and a sleeping end device can't answer the ZDO bind request
      # ("bindRsp after 10000ms"), so failure is the normal case until someone
      # presses the button. Retrying on a timer would just spam the radio; the
      # next z2m restart retries anyway, and the software path
      # (button-dispatcher) keeps the button working meanwhile -- the bind only
      # adds the ability to keep working with this host powered off.
      while read -r from group clusters; do
        echo "binding '$from' -> group '$group' ($clusters)"
        if ! request "device/bind" \
          "$(jq -nc --arg f "$from" --arg t "$group" --argjson c "$clusters" \
             '{from: $f, to: $t, clusters: $c}')"; then
          echo "  bind pending: wake '$from' (press it) and re-run: systemctl start z2m-groups"
        fi
      done < <(
        jq -r --argjson devices "$devices" '
          .[]
          | .group as $group
          | .group_id as $gid
          | .binds[]
          | .from as $from
          | [ $devices[] | select(.friendly_name == $from) | .endpoints[].bindings[]
              | select(.target.type == "group" and .target.id == $gid) | .cluster ] as $bound
          | (.clusters - $bound)
          | select(length > 0)
          | "\($from) \($group) \(tojson)"
        ' "$desired"
      ) || rc=1

      exit "$rc"
    '';
  };
in
{
  systemd.services.z2m-groups = {
    description = "Reconcile zigbee2mqtt group membership from the device registry";
    after = [ "zigbee2mqtt.service" ];
    requires = [ "zigbee2mqtt.service" ];
    # Re-runs whenever z2m restarts, which includes the rebuild that changes
    # the desired state -- the unit's own store path changes too, so a
    # membership edit alone is enough to trigger it.
    wantedBy = [ "zigbee2mqtt.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe reconcile;
      RemainAfterExit = false;
      DynamicUser = true;
    };
  };
}
