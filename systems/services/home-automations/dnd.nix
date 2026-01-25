{
  config,
  pkgs,
  ...
}: let
  # -----------------------------
  # Valid ranges / units (your bulb)
  # -----------------------------
  # Brightness (Home Assistant): 0..255  (or brightness_pct: 0..100)
  # Color temperature: mireds 50..1000  (lower = cooler, higher = warmer)
  # Kelvin equivalent: 1000K..20000K
  #
  # Effects supported by your bulb:
  #   blink, breathe, okay, channel_change, candle,
  #   finish_effect, stop_effect, stop_hue_effect
  # --- Entities / MQTT ---
  livingRoomLight = "light.living_room";
  buttonBTopic = "zigbee2mqtt/Button B/action";

  # --- Presets (mireds: 50..1000) ---
  ctDaylight = 222; # ~6500K (pleasant daylight)
  ctTavern = 333; # ~2700K (warm indoor)
  ctEmbers = 1000; # warmest possible (1000K)

  # --- Brightness (pct: 0..100) ---
  briDaylightPct = 100;
  briTavernPct = 100;
  briEmbersPct = 100; # "intense warm" but still bright
  briCampfirePct = 100;

  # --- Transitions (seconds) ---
  tShort = 3;
  tHold = 2;

  # --- Effect names (must match effect_list strings) ---
  fxCampfire = "candle";
  fxStop1 = "stop_effect";
  fxStop2 = "stop_hue_effect";
in {
  services.home-assistant = {
    config = {
      input_boolean = {
        living_room_campfire = {
          name = "Living room campfire";
          initial = false;
        };

        living_room_ember_mode = {
          name = "Living room ember mode";
          initial = false;
        };
      };

      automation = [
        # ------------------------------------------------------------
        # Button B: HOLD -> Embers (warmest + bright)
        #   - Always applies embers on hold
        #   - Only snapshots the "before" state the FIRST time you enter embers
        # ------------------------------------------------------------
        {
          id = "button_b_hold_living_room_embers";
          alias = "Button B: HOLD -> Living room embers (save state)";
          mode = "restart";

          trigger = [
            {
              platform = "mqtt";
              topic = buttonBTopic;
              payload = "hold";
            }
          ];

          action = [
            # Stop campfire mode/boolean
            {
              service = "input_boolean.turn_off";
              target = {entity_id = "input_boolean.living_room_campfire";};
            }

            # Stop any running bulb effects (send both stop variants)
            {
              service = "light.turn_on";
              target = {entity_id = livingRoomLight;};
              data = {
                effect = fxStop1;
                transition = 1;
              };
            }
            {
              service = "light.turn_on";
              target = {entity_id = livingRoomLight;};
              data = {
                effect = fxStop2;
                transition = 1;
              };
            }

            # If we're NOT already in ember mode: snapshot + mark ember mode
            {
              choose = [
                {
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_boolean.living_room_ember_mode";
                      state = "off";
                    }
                  ];
                  sequence = [
                    {
                      service = "scene.create";
                      data = {
                        scene_id = "living_room_before_embers";
                        snapshot_entities = [livingRoomLight];
                      };
                    }
                    {
                      service = "input_boolean.turn_on";
                      target = {entity_id = "input_boolean.living_room_ember_mode";};
                    }
                  ];
                }
              ];
              default = [];
            }

            # Always apply embers (warmest possible)
            {
              service = "light.turn_on";
              target = {entity_id = livingRoomLight;};
              data = {
                brightness_pct = briEmbersPct; # 0..100
                color_temp = ctEmbers; # 50..1000 (mireds)
                transition = tHold;
              };
            }
          ];
        }

        # ------------------------------------------------------------
        # Button B: DOUBLE -> Toggle campfire using BULB effect ("candle")
        # ------------------------------------------------------------
        {
          id = "button_b_double_toggle_campfire_effect";
          alias = "Button B: DOUBLE -> toggle campfire (bulb effect)";
          mode = "restart";

          trigger = [
            {
              platform = "mqtt";
              topic = buttonBTopic;
              payload = "double";
            }
          ];

          action = [
            {
              choose = [
                # If campfire is ON -> stop it and go to daylight
                {
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_boolean.living_room_campfire";
                      state = "on";
                    }
                  ];
                  sequence = [
                    {
                      service = "input_boolean.turn_off";
                      target = {entity_id = "input_boolean.living_room_campfire";};
                    }
                    {
                      service = "input_boolean.turn_off";
                      target = {entity_id = "input_boolean.living_room_ember_mode";};
                    }

                    {
                      service = "light.turn_on";
                      target = {entity_id = livingRoomLight;};
                      data = {
                        effect = fxStop1;
                        transition = 1;
                      };
                    }
                    {
                      service = "light.turn_on";
                      target = {entity_id = livingRoomLight;};
                      data = {
                        effect = fxStop2;
                        transition = 1;
                      };
                    }

                    {
                      service = "light.turn_on";
                      target = {entity_id = livingRoomLight;};
                      data = {
                        brightness_pct = briDaylightPct;
                        color_temp = ctDaylight;
                        transition = tShort;
                      };
                    }
                  ];
                }
              ];

              # Else start campfire effect
              default = [
                {
                  service = "input_boolean.turn_off";
                  target = {entity_id = "input_boolean.living_room_ember_mode";};
                }
                {
                  service = "input_boolean.turn_on";
                  target = {entity_id = "input_boolean.living_room_campfire";};
                }

                # Warm base state first (optional but helps the vibe)
                {
                  service = "light.turn_on";
                  target = {entity_id = livingRoomLight;};
                  data = {
                    brightness_pct = briCampfirePct;
                    color_temp = 454; # ~2200K (candle-y but not ultra-dim like 900 mired)
                    transition = tShort;
                  };
                }

                # Enable candle effect FIRST
                {
                  service = "light.turn_on";
                  target = {entity_id = livingRoomLight;};
                  data = {effect = fxCampfire;};
                }

                # Small delay, then re-assert brightness (and color temp) so it doesn't stay dim
                {delay = "00:00:00.300";}

                {
                  service = "light.turn_on";
                  target = {entity_id = livingRoomLight;};
                  data = {
                    brightness_pct = briCampfirePct;
                    # optional: keep a warm temp while the effect runs
                    color_temp = 454;
                  };
                }
              ];
            }
          ];
        }

        # ------------------------------------------------------------
        # Button B: SINGLE -> smart click
        #   1) if campfire -> daylight (stop effect)
        #   2) else if embers -> restore snapshot
        #   3) else toggle tavern <-> daylight
        # ------------------------------------------------------------
        {
          id = "button_b_single_smart_toggle";
          alias = "Button B: SINGLE -> smart toggle";
          mode = "restart";

          trigger = [
            {
              platform = "mqtt";
              topic = buttonBTopic;
              payload = "single";
            }
          ];

          action = [
            {
              choose = [
                # 1) campfire -> daylight
                {
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_boolean.living_room_campfire";
                      state = "on";
                    }
                  ];
                  sequence = [
                    {
                      service = "input_boolean.turn_off";
                      target = {entity_id = "input_boolean.living_room_campfire";};
                    }
                    {
                      service = "input_boolean.turn_off";
                      target = {entity_id = "input_boolean.living_room_ember_mode";};
                    }

                    {
                      service = "light.turn_on";
                      target = {entity_id = livingRoomLight;};
                      data = {
                        effect = fxStop1;
                        transition = 1;
                      };
                    }
                    {
                      service = "light.turn_on";
                      target = {entity_id = livingRoomLight;};
                      data = {
                        effect = fxStop2;
                        transition = 1;
                      };
                    }

                    {
                      service = "light.turn_on";
                      target = {entity_id = livingRoomLight;};
                      data = {
                        brightness_pct = briDaylightPct;
                        color_temp = ctDaylight;
                        transition = tShort;
                      };
                    }
                  ];
                }

                # 2) embers -> restore previous state
                {
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_boolean.living_room_ember_mode";
                      state = "on";
                    }
                  ];
                  sequence = [
                    {
                      service = "light.turn_on";
                      target = {entity_id = livingRoomLight;};
                      data = {
                        effect = fxStop1;
                        transition = 1;
                      };
                    }
                    {
                      service = "light.turn_on";
                      target = {entity_id = livingRoomLight;};
                      data = {
                        effect = fxStop2;
                        transition = 1;
                      };
                    }

                    {
                      service = "scene.turn_on";
                      target = {entity_id = "scene.living_room_before_embers";};
                    }
                    {
                      service = "input_boolean.turn_off";
                      target = {entity_id = "input_boolean.living_room_ember_mode";};
                    }
                  ];
                }

                # 3) if currently warm-ish -> go daylight
                {
                  conditions = [
                    {
                      condition = "template";
                      value_template = "{{ (state_attr('light.living_room','color_temp') | int(0)) > 300 }}";
                    }
                  ];
                  sequence = [
                    {
                      service = "light.turn_on";
                      target = {entity_id = livingRoomLight;};
                      data = {
                        brightness_pct = briDaylightPct;
                        color_temp = ctDaylight;
                        transition = tShort;
                      };
                    }
                  ];
                }
              ];

              # default: go tavern
              default = [
                {
                  service = "input_boolean.turn_off";
                  target = {entity_id = "input_boolean.living_room_ember_mode";};
                }
                {
                  service = "light.turn_on";
                  target = {entity_id = livingRoomLight;};
                  data = {
                    brightness_pct = briTavernPct;
                    color_temp = ctTavern;
                    transition = tShort;
                  };
                }
              ];
            }
          ];
        }
      ];
    };
  };
}
