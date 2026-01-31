{
  config,
  pkgs,
  ...
}: let
  motionSensorTopic = "zigbee2mqtt/motion sensor";
  targetSwitch = "switch.living_room_plug";

  enabledEntity = "input_boolean.motion_doorbell_enabled";
  cooldownEntity = "input_number.motion_doorbell_cooldown";
  lastTriggeredEntity = "input_datetime.motion_doorbell_last_triggered";

  defaultCooldownSec = 10;
  flashDurationSec = 1;
in {
  services.home-assistant = {
    config = {
      input_boolean = {
        motion_doorbell_enabled = {
          name = "Motion doorbell enabled";
          initial = true;
          icon = "mdi:cat";
        };
      };

      input_number = {
        motion_doorbell_cooldown = {
          name = "Motion doorbell cooldown";
          min = 0;
          max = 60;
          step = 5;
          mode = "slider";
          unit_of_measurement = "s";
          initial = defaultCooldownSec;
          icon = "mdi:timer-sand";
        };
      };

      input_datetime = {
        motion_doorbell_last_triggered = {
          name = "Motion doorbell last triggered";
          has_date = true;
          has_time = true;
          icon = "mdi:clock-outline";
        };
      };

      script = {
        motion_doorbell_flash = {
          alias = "Motion doorbell flash";
          mode = "single"; # Prevent overlapping flashes
          sequence = [
            {
              service = "switch.toggle";
              target = {entity_id = targetSwitch;};
            }
            {delay = {seconds = flashDurationSec;};}
            {
              service = "switch.toggle";
              target = {entity_id = targetSwitch;};
            }
          ];
        };
      };

      automation = [
        {
          id = "motion_doorbell_on_motion";
          alias = "Motion doorbell: flash on motion";
          mode = "single";

          trigger = [
            {
              platform = "mqtt";
              topic = motionSensorTopic;
              value_template = "{{ value_json.motion_state }}";
              payload = "small";
              id = "motion_small";
            }
            {
              platform = "mqtt";
              topic = motionSensorTopic;
              value_template = "{{ value_json.motion_state }}";
              payload = "large";
              id = "motion_large";
            }
          ];

          condition = [
            {
              condition = "state";
              entity_id = enabledEntity;
              state = "on";
            }
            {
              condition = "template";
              value_template =
                "{% set last = states('${lastTriggeredEntity}') %}"
                + "{% if last in ('unknown', 'unavailable', 'none', '') %}"
                + "true"
                + "{% else %}"
                + "{% set last_ts = as_timestamp(last, 0) %}"
                + "{% set cooldown = states('${cooldownEntity}') | float(${toString defaultCooldownSec}) %}"
                + "{{ (as_timestamp(now()) - last_ts) >= cooldown }}"
                + "{% endif %}";
            }
          ];

          action = [
            {
              service = "input_datetime.set_datetime";
              target = {entity_id = lastTriggeredEntity;};
              data = {
                datetime = "{{ now().strftime('%Y-%m-%d %H:%M:%S') }}";
              };
            }
            {service = "script.motion_doorbell_flash";}
          ];
        }
      ];
    };
  };
}
