{
  config,
  pkgs,
  ...
}: let
  # --- Entities / MQTT ---
  livingRoomLight = "light.living_room";
  buttonBTopic = "zigbee2mqtt/Button B/action";

  # --- Presets (mireds: 50..1000) ---
  ctDaylight = 222; # ~6500K
  ctTavern = 333; # ~2700K
  ctEmbers = 1000; # warmest possible

  # --- Brightness presets (pct: 0..100) ---
  briDaylightPct = 100;
  briTavernPct = 100;

  # ------------------------------------------------------------
  # MASTER BRIGHTNESS (slider multiplier)
  # ------------------------------------------------------------
  masterBriEntity = "input_number.living_room_master_brightness"; # 0..120 (%)

  # Campfire (BRIGHT, dynamic but not dim) — softened + slower
  campfireBaseBriPct = 75; # starting point (pre-master)
  campfireBriMinPct = 72; # gentler wander min
  campfireBriMaxPct = 78; # gentler wander max

  campfireLickMinPct = 84; # softer spike min
  campfireLickMaxPct = 94; # softer spike max
  campfireLickChancePct = 10; # fewer spikes

  # Campfire color temp wander (stay warm, but vary)
  campfireCtMin = 410; # slightly tighter (warm)
  campfireCtMax = 500; # slightly tighter (still warm)
  campfireBaseCt = 450; # cozy base

  # Embers (BRIGHT and slow pulse) — base 85%, +/- 5%
  embersBaseBriPct = 85;

  # "Down" part of the pulse: 80–82% (stays near -5%)
  embersLowMinPct = 80;
  embersLowMaxPct = 82;

  # "Up" part of the pulse: 88–90% (stays near +5%)
  embersHighMinPct = 88;
  embersHighMaxPct = 90;

  # --- Timing (seconds) ---
  tShort = 3;

  # Campfire loop timing (slower)
  campfireTransMin = 3;
  campfireTransMax = 6;
  campfireDelayMin = 3;
  campfireDelayMax = 6;

  # Lick timing (seconds, small but not “strobe”)
  lickOnHold = "00:00:00.22";
  lickOffHold = "00:00:00.30";

  # Embers pulse timing
  embersTransMin = 6;
  embersTransMax = 12;
  embersDelayMin = 7;
  embersDelayMax = 12;
in {
  services.home-assistant = {
    config = {
      # ------------------------------------------------------------
      # Helpers: mode flags + master brightness slider
      # ------------------------------------------------------------
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

      # MASTER slider (0..120, default 100)
      input_number = {
        living_room_master_brightness = {
          name = "Living room master brightness";
          min = 0;
          max = 120;
          step = 1;
          mode = "slider";
          unit_of_measurement = "%";
          initial = 100;
          icon = "mdi:brightness-percent";
        };
      };

      # ------------------------------------------------------------
      # Scripts: behavior lives here
      # ------------------------------------------------------------
      script = {
        # Snapshot only when entering FX from "normal"
        living_room_snapshot_if_needed = {
          alias = "Living room: snapshot (if entering FX)";
          mode = "restart";
          sequence = [
            {
              choose = [
                {
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_boolean.living_room_campfire";
                      state = "off";
                    }
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
                        scene_id = "living_room_before_fx";
                        snapshot_entities = [livingRoomLight];
                      };
                    }
                  ];
                }
              ];
              default = [];
            }
          ];
        };

        living_room_set_daylight = {
          alias = "Living room: set daylight";
          mode = "restart";
          sequence = [
            {
              service = "light.turn_on";
              target = {entity_id = livingRoomLight;};
              data = {
                # Apply master brightness
                brightness_pct =
                  "{% set m = (states('${masterBriEntity}')|float(100))/100 %}"
                  + "{% set v = (${builtins.toString briDaylightPct}) * m %}"
                  + "{{ [100, [1, v|round(0)|int] | max] | min }}";
                color_temp = ctDaylight;
                transition = tShort;
              };
            }
          ];
        };

        living_room_set_tavern = {
          alias = "Living room: set tavern";
          mode = "restart";
          sequence = [
            {
              service = "light.turn_on";
              target = {entity_id = livingRoomLight;};
              data = {
                # Apply master brightness
                brightness_pct =
                  "{% set m = (states('${masterBriEntity}')|float(100))/100 %}"
                  + "{% set v = (${builtins.toString briTavernPct}) * m %}"
                  + "{{ [100, [1, v|round(0)|int] | max] | min }}";
                color_temp = ctTavern;
                transition = tShort;
              };
            }
          ];
        };

        living_room_restore_snapshot = {
          alias = "Living room: restore snapshot";
          mode = "restart";
          sequence = [
            {
              service = "scene.turn_on";
              target = {entity_id = "scene.living_room_before_fx";};
            }
          ];
        };

        # Stop FX loops + clear flags (does not change light state)
        living_room_stop_fx = {
          alias = "Living room: stop FX loops";
          mode = "restart";
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
              service = "script.turn_off";
              target = {entity_id = ["script.living_room_campfire_on" "script.living_room_embers_on"];};
            }
          ];
        };

        # ------------------------------------------------------------
        # CAMPFIRE (dynamic, BRIGHT) — slowed + less intense
        # ------------------------------------------------------------
        living_room_campfire_on = {
          alias = "Living room: campfire ON (dynamic, bright)";
          mode = "restart";
          sequence = [
            {service = "script.living_room_snapshot_if_needed";}

            # Ensure only one FX loop is running
            {
              service = "input_boolean.turn_off";
              target = {entity_id = "input_boolean.living_room_ember_mode";};
            }
            {
              service = "script.turn_off";
              target = {entity_id = "script.living_room_embers_on";};
            }

            {
              service = "input_boolean.turn_on";
              target = {entity_id = "input_boolean.living_room_campfire";};
            }

            # Bright warm base (with master)
            {
              service = "light.turn_on";
              target = {entity_id = livingRoomLight;};
              data = {
                brightness_pct =
                  "{% set m = (states('${masterBriEntity}')|float(100))/100 %}"
                  + "{% set v = (${builtins.toString campfireBaseBriPct}) * m %}"
                  + "{{ [100, [1, v|round(0)|int] | max] | min }}";
                color_temp = campfireBaseCt;
                transition = 2;
              };
            }

            {
              repeat = {
                while = [
                  {
                    condition = "state";
                    entity_id = "input_boolean.living_room_campfire";
                    state = "on";
                  }
                ];
                sequence = [
                  # Gentle bright wander (with master)
                  {
                    service = "light.turn_on";
                    target = {entity_id = livingRoomLight;};
                    data = {
                      brightness_pct =
                        "{% set m = (states('${masterBriEntity}')|float(100))/100 %}"
                        + "{% set raw = range(${builtins.toString campfireBriMinPct}, ${builtins.toString (campfireBriMaxPct + 1)}) | random %}"
                        + "{% set v = raw * m %}"
                        + "{{ [100, [1, v|round(0)|int] | max] | min }}";
                      color_temp = "{{ range(" + builtins.toString campfireCtMin + ", " + builtins.toString (campfireCtMax + 1) + ") | random }}";
                      transition = "{{ range(" + builtins.toString campfireTransMin + ", " + builtins.toString (campfireTransMax + 1) + ") | random }}";
                    };
                  }

                  {delay = "00:00:{{ range(" + builtins.toString campfireDelayMin + ", " + builtins.toString (campfireDelayMax + 1) + ") | random }}";}

                  # Occasional "lick" (quick bright spike) (with master)
                  {
                    choose = [
                      {
                        conditions = [
                          {
                            condition = "template";
                            value_template = "{{ (range(1, 101) | random) <= " + builtins.toString campfireLickChancePct + " }}";
                          }
                        ];
                        sequence = [
                          {
                            service = "light.turn_on";
                            target = {entity_id = livingRoomLight;};
                            data = {
                              brightness_pct =
                                "{% set m = (states('${masterBriEntity}')|float(100))/100 %}"
                                + "{% set raw = range(${builtins.toString campfireLickMinPct}, ${builtins.toString (campfireLickMaxPct + 1)}) | random %}"
                                + "{% set v = raw * m %}"
                                + "{{ [100, [1, v|round(0)|int] | max] | min }}";
                              color_temp = "{{ range(" + builtins.toString campfireCtMin + ", " + builtins.toString (campfireCtMax + 1) + ") | random }}";
                              transition = 0;
                            };
                          }
                          {delay = lickOnHold;}
                          {
                            service = "light.turn_on";
                            target = {entity_id = livingRoomLight;};
                            data = {
                              brightness_pct =
                                "{% set m = (states('${masterBriEntity}')|float(100))/100 %}"
                                + "{% set raw = range(${builtins.toString campfireBriMinPct}, ${builtins.toString (campfireBriMaxPct + 1)}) | random %}"
                                + "{% set v = raw * m %}"
                                + "{{ [100, [1, v|round(0)|int] | max] | min }}";
                              color_temp = "{{ range(" + builtins.toString campfireCtMin + ", " + builtins.toString (campfireCtMax + 1) + ") | random }}";
                              transition = 2;
                            };
                          }
                          {delay = lickOffHold;}
                        ];
                      }
                    ];
                    default = [];
                  }
                ];
              };
            }
          ];
        };

        living_room_campfire_off_to_daylight = {
          alias = "Living room: campfire OFF -> daylight";
          mode = "restart";
          sequence = [
            {
              service = "input_boolean.turn_off";
              target = {entity_id = "input_boolean.living_room_campfire";};
            }
            {
              service = "script.turn_off";
              target = {entity_id = "script.living_room_campfire_on";};
            }
            {service = "script.living_room_set_daylight";}
          ];
        };

        # ------------------------------------------------------------
        # EMBERS (slow pulse, BRIGHT)
        # ------------------------------------------------------------
        living_room_embers_on = {
          alias = "Living room: embers ON (slow pulse, bright)";
          mode = "restart";
          sequence = [
            {service = "script.living_room_snapshot_if_needed";}

            # Ensure only one FX loop is running
            {
              service = "input_boolean.turn_off";
              target = {entity_id = "input_boolean.living_room_campfire";};
            }
            {
              service = "script.turn_off";
              target = {entity_id = "script.living_room_campfire_on";};
            }

            {
              service = "input_boolean.turn_on";
              target = {entity_id = "input_boolean.living_room_ember_mode";};
            }

            # Bright warm base (with master)
            {
              service = "light.turn_on";
              target = {entity_id = livingRoomLight;};
              data = {
                brightness_pct =
                  "{% set m = (states('${masterBriEntity}')|float(100))/100 %}"
                  + "{% set v = (${builtins.toString embersBaseBriPct}) * m %}"
                  + "{{ [100, [1, v|round(0)|int] | max] | min }}";
                color_temp = ctEmbers;
                transition = 3;
              };
            }

            {
              repeat = {
                while = [
                  {
                    condition = "state";
                    entity_id = "input_boolean.living_room_ember_mode";
                    state = "on";
                  }
                ];
                sequence = [
                  # breathe up (with master)
                  {
                    service = "light.turn_on";
                    target = {entity_id = livingRoomLight;};
                    data = {
                      brightness_pct =
                        "{% set m = (states('${masterBriEntity}')|float(100))/100 %}"
                        + "{% set raw = range(${builtins.toString embersHighMinPct}, ${builtins.toString (embersHighMaxPct + 1)}) | random %}"
                        + "{% set v = raw * m %}"
                        + "{{ [100, [1, v|round(0)|int] | max] | min }}";
                      color_temp = ctEmbers;
                      transition = "{{ range(" + builtins.toString embersTransMin + ", " + builtins.toString (embersTransMax + 1) + ") | random }}";
                    };
                  }
                  {delay = "00:00:{{ range(" + builtins.toString embersDelayMin + ", " + builtins.toString (embersDelayMax + 1) + ") | random }}";}

                  # breathe down (with master)
                  {
                    service = "light.turn_on";
                    target = {entity_id = livingRoomLight;};
                    data = {
                      brightness_pct =
                        "{% set m = (states('${masterBriEntity}')|float(100))/100 %}"
                        + "{% set raw = range(${builtins.toString embersLowMinPct}, ${builtins.toString (embersLowMaxPct + 1)}) | random %}"
                        + "{% set v = raw * m %}"
                        + "{{ [100, [1, v|round(0)|int] | max] | min }}";
                      color_temp = ctEmbers;
                      transition = "{{ range(" + builtins.toString embersTransMin + ", " + builtins.toString (embersTransMax + 1) + ") | random }}";
                    };
                  }
                  {delay = "00:00:{{ range(" + builtins.toString embersDelayMin + ", " + builtins.toString (embersDelayMax + 1) + ") | random }}";}
                ];
              };
            }
          ];
        };

        living_room_restore_from_embers = {
          alias = "Living room: embers OFF -> restore snapshot";
          mode = "restart";
          sequence = [
            {
              service = "input_boolean.turn_off";
              target = {entity_id = "input_boolean.living_room_ember_mode";};
            }
            {
              service = "script.turn_off";
              target = {entity_id = "script.living_room_embers_on";};
            }
            {service = "script.living_room_restore_snapshot";}
          ];
        };
      };

      # ------------------------------------------------------------
      # Automations: button routes to scripts
      # ------------------------------------------------------------
      automation = [
        # HOLD -> Embers pulse
        {
          id = "button_b_hold_living_room_embers";
          alias = "Button B: HOLD -> Living room embers (pulsing, bright)";
          mode = "restart";
          trigger = [
            {
              platform = "mqtt";
              topic = buttonBTopic;
              payload = "hold";
            }
          ];
          action = [
            {service = "script.living_room_embers_on";}
          ];
        }

        # DOUBLE -> Toggle campfire
        {
          id = "button_b_double_toggle_campfire";
          alias = "Button B: DOUBLE -> toggle campfire (dynamic, bright)";
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
                {
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_boolean.living_room_campfire";
                      state = "on";
                    }
                  ];
                  sequence = [
                    {service = "script.living_room_campfire_off_to_daylight";}
                  ];
                }
              ];
              default = [
                {service = "script.living_room_campfire_on";}
              ];
            }
          ];
        }

        # SINGLE -> smart toggle
        {
          id = "button_b_single_smart_toggle";
          alias = "Button B: SINGLE -> smart toggle (FX-aware)";
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
                # campfire -> daylight
                {
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_boolean.living_room_campfire";
                      state = "on";
                    }
                  ];
                  sequence = [
                    {service = "script.living_room_campfire_off_to_daylight";}
                  ];
                }

                # embers -> restore
                {
                  conditions = [
                    {
                      condition = "state";
                      entity_id = "input_boolean.living_room_ember_mode";
                      state = "on";
                    }
                  ];
                  sequence = [
                    {service = "script.living_room_restore_from_embers";}
                  ];
                }

                # warm-ish -> daylight
                {
                  conditions = [
                    {
                      condition = "template";
                      value_template = "{{ (state_attr('light.living_room','color_temp') | int(0)) > 300 }}";
                    }
                  ];
                  sequence = [
                    {service = "script.living_room_set_daylight";}
                  ];
                }
              ];

              # default: tavern
              default = [
                {service = "script.living_room_set_tavern";}
              ];
            }
          ];
        }
      ];
    };
  };
}
