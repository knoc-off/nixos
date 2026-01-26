{
  config,
  pkgs,
  ...
}: let
  # --- Entities ---
  bedroomLight = "light.bedroom_light";
  bedroomPlug = "switch.bedroom_plug";
  buttonATopic = "zigbee2mqtt/Button A/action";

  # --- Helper entities ---
  plugTimerSelect = "input_select.plug_auto_off";
  sunriseTimeEntity = "input_datetime.bedroom_sunrise_time";

  # --- Sunrise defaults ---
  sunriseDefaultTime = "07:00:00";

  # --- Light settings ---
  sunriseWarmColorTemp = 400; # warm (mireds)
  sunriseCoolColorTemp = 250; # cooler daylight
  bedtimeFadeDurationSec = 1800; # 30 minutes
in {
  services.home-assistant = {
    config = {
      # ------------------------------------------------------------------
      # Helpers
      # ------------------------------------------------------------------
      input_select = {
        plug_auto_off = {
          name = "Plug auto-off timer";
          options = [
            "30 minutes"
            "1 hour"
            "2 hours"
            "8 hours"
          ];
          initial = "1 hour";
        };
      };

      input_datetime = {
        bedroom_sunrise_time = {
          name = "Bedroom sunrise time";
          has_date = false;
          has_time = true;
          initial = sunriseDefaultTime;
          icon = "mdi:weather-sunset-up";
        };
      };

      # ------------------------------------------------------------------
      # Scripts
      # ------------------------------------------------------------------
      script = {
        # --------------------------------------------------------------
        # Plug auto-off: dynamic delay based on input_select
        # --------------------------------------------------------------
        bedroom_plug_auto_off = {
          alias = "Bedroom plug auto-off";
          mode = "restart";
          sequence = [
            # Dynamic delay based on selected duration
            {
              delay = ''
                {% set sel = states('${plugTimerSelect}') %}
                {% if sel == '30 minutes' %}
                  00:30:00
                {% elif sel == '1 hour' %}
                  01:00:00
                {% elif sel == '2 hours' %}
                  02:00:00
                {% elif sel == '8 hours' %}
                  08:00:00
                {% else %}
                  00:00:30
                {% endif %}
              '';
            }
            # Only turn off if still on
            {
              condition = "state";
              entity_id = bedroomPlug;
              state = "on";
            }
            {
              service = "switch.turn_off";
              target = {entity_id = bedroomPlug;};
            }
          ];
        };

        # --------------------------------------------------------------
        # Sunrise ramp: 2-hour gradual brightness increase
        # Hour 1: brightness 1->60, warm color temp
        # Hour 2: brightness 60->300, shift to cooler
        # --------------------------------------------------------------
        bedroom_sunrise_ramp = {
          alias = "Bedroom sunrise ramp";
          mode = "restart";
          sequence = [
            # Start at minimum brightness, warm color
            {
              service = "light.turn_on";
              target = {entity_id = bedroomLight;};
              data = {
                brightness = 1;
                color_temp = sunriseWarmColorTemp;
              };
            }

            # Phase 1: 60 steps over 60 minutes (1 step/min)
            # brightness 1 -> ~60
            {
              repeat = {
                count = 60;
                sequence = [
                  {delay = "00:01:00";}
                  {
                    service = "light.turn_on";
                    target = {entity_id = bedroomLight;};
                    data = {
                      brightness_step = 1;
                      transition = 1;
                      color_temp = sunriseWarmColorTemp;
                    };
                  }
                ];
              };
            }

            # Phase 2: 60 steps over 60 minutes
            # brightness ~60 -> ~300, shift to cooler color
            {
              repeat = {
                count = 60;
                sequence = [
                  {delay = "00:01:00";}
                  {
                    service = "light.turn_on";
                    target = {entity_id = bedroomLight;};
                    data = {
                      brightness_step = 4;
                      transition = 1;
                      color_temp = sunriseCoolColorTemp;
                    };
                  }
                ];
              };
            }
          ];
        };

        # --------------------------------------------------------------
        # Bedtime fade: dim to 10%, then fade off over 30 minutes
        # --------------------------------------------------------------
        bedroom_light_bedtime_fade = {
          alias = "Bedroom light bedtime fade";
          mode = "restart";
          sequence = [
            # Set to 10% brightness
            {
              service = "light.turn_on";
              target = {entity_id = bedroomLight;};
              data = {brightness_pct = 10;};
            }
            # Small pause for brightness to take effect
            {delay = {seconds = 1;};}
            # Fade to off over 30 minutes
            {
              service = "light.turn_off";
              target = {entity_id = bedroomLight;};
              data = {
                transition = bedtimeFadeDurationSec;
              };
            }
          ];
        };
      };

      # ------------------------------------------------------------------
      # Automations
      # ------------------------------------------------------------------
      automation = [
        # --------------------------------------------------------------
        # Plug auto-off: trigger when plug turns on
        # --------------------------------------------------------------
        {
          id = "bedroom_plug_auto_off_trigger";
          alias = "Bedroom plug auto-off trigger";
          mode = "restart";
          trigger = [
            {
              platform = "state";
              entity_id = bedroomPlug;
              to = "on";
            }
          ];
          action = [
            {service = "script.bedroom_plug_auto_off";}
          ];
        }

        # --------------------------------------------------------------
        # Sunrise: trigger at configured time
        # --------------------------------------------------------------
        {
          id = "bedroom_sunrise_at_configured_time";
          alias = "Bedroom sunrise at configured time";
          mode = "restart";
          trigger = [
            {
              platform = "time";
              at = sunriseTimeEntity;
            }
          ];
          action = [
            {service = "script.bedroom_sunrise_ramp";}
          ];
        }

        # --------------------------------------------------------------
        # Button A: single = toggle, hold = bedtime fade
        # --------------------------------------------------------------
        {
          id = "button_a_bedroom_light";
          alias = "Button A: bedroom light toggle / bedtime fade";
          mode = "restart";
          trigger = [
            {
              platform = "mqtt";
              topic = buttonATopic;
              payload = "single";
              id = "single";
            }
            {
              platform = "mqtt";
              topic = buttonATopic;
              payload = "hold";
              id = "hold";
            }
          ];
          action = [
            {
              choose = [
                # Single press: toggle light
                {
                  conditions = [
                    {
                      condition = "trigger";
                      id = "single";
                    }
                  ];
                  sequence = [
                    {
                      service = "light.toggle";
                      target = {entity_id = bedroomLight;};
                    }
                  ];
                }
                # Hold: bedtime fade
                {
                  conditions = [
                    {
                      condition = "trigger";
                      id = "hold";
                    }
                  ];
                  sequence = [
                    {service = "script.bedroom_light_bedtime_fade";}
                  ];
                }
              ];
            }
          ];
        }
      ];
    };
  };
}
