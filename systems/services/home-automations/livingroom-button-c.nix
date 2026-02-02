{
  config,
  pkgs,
  ...
}: let
  # --- Entities ---
  livingRoomLight = "light.living_room";
  buttonCTopic = "zigbee2mqtt/Button C/action";

  # --- Color temperatures (mireds) ---
  ctNeutral = 250; # ~4000K neutral
  ctWarmer = 370; # ~2700K warmer
in {
  services.home-assistant = {
    config = {
      automation = [
        # --------------------------------------------------------------
        # Button C: single = toggle on/off, double = toggle color temp
        # --------------------------------------------------------------
        {
          id = "button_c_livingroom_light";
          alias = "Button C: living room light toggle / color temp";
          mode = "restart";
          trigger = [
            {
              platform = "mqtt";
              topic = buttonCTopic;
              payload = "single";
              id = "single";
            }
            {
              platform = "mqtt";
              topic = buttonCTopic;
              payload = "double";
              id = "double";
            }
          ];
          action = [
            {
              choose = [
                # Single press: toggle light (100% brightness when on)
                {
                  conditions = [
                    {
                      condition = "trigger";
                      id = "single";
                    }
                  ];
                  sequence = [
                    {
                      choose = [
                        # Light is off -> turn on at 100%
                        {
                          conditions = [
                            {
                              condition = "state";
                              entity_id = livingRoomLight;
                              state = "off";
                            }
                          ];
                          sequence = [
                            {
                              service = "light.turn_on";
                              target = {entity_id = livingRoomLight;};
                              data = {
                                brightness_pct = 100;
                              };
                            }
                          ];
                        }
                      ];
                      # Light is on -> turn off
                      default = [
                        {
                          service = "light.turn_off";
                          target = {entity_id = livingRoomLight;};
                        }
                      ];
                    }
                  ];
                }

                # Double press: toggle color temp (only if light is on)
                {
                  conditions = [
                    {
                      condition = "trigger";
                      id = "double";
                    }
                    {
                      condition = "state";
                      entity_id = livingRoomLight;
                      state = "on";
                    }
                  ];
                  sequence = [
                    {
                      choose = [
                        # Currently warm-ish (> 300 mireds) -> set to neutral
                        {
                          conditions = [
                            {
                              condition = "template";
                              value_template = "{{ (state_attr('${livingRoomLight}', 'color_temp') | int(0)) > 300 }}";
                            }
                          ];
                          sequence = [
                            {
                              service = "light.turn_on";
                              target = {entity_id = livingRoomLight;};
                              data = {
                                color_temp = ctNeutral;
                              };
                            }
                          ];
                        }
                      ];
                      # Currently neutral/cool -> set to warmer
                      default = [
                        {
                          service = "light.turn_on";
                          target = {entity_id = livingRoomLight;};
                          data = {
                            color_temp = ctWarmer;
                          };
                        }
                      ];
                    }
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
